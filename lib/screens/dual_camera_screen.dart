import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:gal/gal.dart';

class DualCameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const DualCameraScreen({super.key, required this.cameras});

  @override
  State<DualCameraScreen> createState() => _DualCameraScreenState();
}

class _DualCameraScreenState extends State<DualCameraScreen>
    with WidgetsBindingObserver {
  // ── Kontrolery ──
  CameraController? _backCtrl;
  CameraController? _frontCtrl;

  // ── Stan ──
  bool _initialized = false;
  bool _isRecording = false;
  bool _isBusy = false;
  int _recSeconds = 0;
  Timer? _recTimer;
  String? _error;
  File? _lastPhoto;

  // Czy PiP jest przeciągany (drag)
  Offset _pipOffset = Offset.zero; // inicjalizujemy w build
  bool _pipOffsetSet = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addObserver(this);
    _requestPermissionsAndInit();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recTimer?.cancel();
    _backCtrl?.dispose();
    _frontCtrl?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_initialized) return;
    if (state == AppLifecycleState.inactive) {
      _backCtrl?.dispose();
      _frontCtrl?.dispose();
      if (mounted) setState(() => _initialized = false);
    } else if (state == AppLifecycleState.resumed) {
      _initCameras();
    }
  }

  // ─────────────────────────────────────────
  // UPRAWNIENIA + INICJALIZACJA
  // ─────────────────────────────────────────

  Future<void> _requestPermissionsAndInit() async {
    final statuses = await [
      Permission.camera,
      Permission.microphone,
      Permission.storage,
      Permission.photos,
      Permission.videos,
    ].request();

    if (!(statuses[Permission.camera]?.isGranted ?? false)) {
      setState(() =>
          _error = 'Brak uprawnień do kamery.\nZezwól w Ustawieniach telefonu.');
      return;
    }
    if (!(statuses[Permission.microphone]?.isGranted ?? false)) {
      _showSnack('⚠️ Brak mikrofonu – nagrywanie bez dźwięku');
    }

    await _initCameras();
  }

  Future<void> _initCameras() async {
    setState(() {
      _initialized = false;
      _error = null;
    });

    if (widget.cameras.length < 2) {
      setState(() => _error = 'Urządzenie nie posiada dwóch kamer.');
      return;
    }

    CameraDescription? back;
    CameraDescription? front;
    for (final cam in widget.cameras) {
      if (cam.lensDirection == CameraLensDirection.back) back ??= cam;
      if (cam.lensDirection == CameraLensDirection.front) front ??= cam;
    }

    if (back == null || front == null) {
      setState(() => _error = 'Nie znaleziono kamery przedniej lub tylnej.');
      return;
    }

    // S25 Ultra: tylna w max rozdzielczości, przednia w high
    _backCtrl = CameraController(
      back,
      ResolutionPreset.veryHigh,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _frontCtrl = CameraController(
      front,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await Future.wait([
        _backCtrl!.initialize(),
        _frontCtrl!.initialize(),
      ]);
      // Blokada autofokusa i ekspozycji dla tylnej
      await _backCtrl!.setFocusMode(FocusMode.auto);
      await _backCtrl!.setExposureMode(ExposureMode.auto);
      if (mounted) setState(() => _initialized = true);
    } catch (e) {
      setState(() => _error = 'Błąd inicjalizacji kamer:\n$e');
    }
  }

  // ─────────────────────────────────────────
  // ZDJĘCIA
  // ─────────────────────────────────────────

  Future<void> _takePhotos() async {
    if (!_initialized || _isBusy || _isRecording) return;
    setState(() => _isBusy = true);

    try {
      final results = await Future.wait([
        _backCtrl!.takePicture(),
        _frontCtrl!.takePicture(),
      ]);

      final dir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;

      final backFile = File(p.join(dir.path, 'back_$ts.jpg'));
      final frontFile = File(p.join(dir.path, 'front_$ts.jpg'));

      await Future.wait([
        backFile.writeAsBytes(await File(results[0].path).readAsBytes()),
        frontFile.writeAsBytes(await File(results[1].path).readAsBytes()),
      ]);

      await Future.wait([
        Gal.putImage(backFile.path, album: 'DualCamera'),
        Gal.putImage(frontFile.path, album: 'DualCamera'),
      ]);

      if (mounted) {
        setState(() => _lastPhoto = backFile);
        _showSnack('📸 Dwa zdjęcia zapisane w albumie DualCamera!');
      }
    } catch (e) {
      _showSnack('Błąd zdjęcia: $e');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  // ─────────────────────────────────────────
  // NAGRYWANIE
  // ─────────────────────────────────────────

  Future<void> _toggleRecording() async {
    if (!_initialized || _isBusy) return;
    _isRecording ? await _stopRecording() : await _startRecording();
  }

  Future<void> _startRecording() async {
    setState(() => _isBusy = true);
    try {
      await Future.wait([
        _backCtrl!.startVideoRecording(),
        _frontCtrl!.startVideoRecording(),
      ]);
      _recSeconds = 0;
      _recTimer = Timer.periodic(
          const Duration(seconds: 1), (_) => setState(() => _recSeconds++));
      setState(() {
        _isRecording = true;
        _isBusy = false;
      });
    } catch (e) {
      setState(() => _isBusy = false);
      _showSnack('Błąd startu nagrywania: $e');
    }
  }

  Future<void> _stopRecording() async {
    _recTimer?.cancel();
    setState(() => _isBusy = true);
    try {
      final results = await Future.wait([
        _backCtrl!.stopVideoRecording(),
        _frontCtrl!.stopVideoRecording(),
      ]);

      final dir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;

      final backVid = File(p.join(dir.path, 'back_$ts.mp4'));
      final frontVid = File(p.join(dir.path, 'front_$ts.mp4'));

      await Future.wait([
        backVid.writeAsBytes(await File(results[0].path).readAsBytes()),
        frontVid.writeAsBytes(await File(results[1].path).readAsBytes()),
      ]);
      await Future.wait([
        Gal.putVideo(backVid.path, album: 'DualCamera'),
        Gal.putVideo(frontVid.path, album: 'DualCamera'),
      ]);

      if (mounted) _showSnack('🎬 Wideo z obu kamer zapisane!');
    } catch (e) {
      _showSnack('Błąd zatrzymania: $e');
    } finally {
      if (mounted)
        setState(() {
          _isRecording = false;
          _isBusy = false;
        });
    }
  }

  // ─────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────

  String _fmtTime(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 14)),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        duration: const Duration(seconds: 2),
      ));
  }

  // ─────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) return _buildError();
    if (!_initialized) return _buildLoading();
    return _buildCameraLayout();
  }

  // ── Główny układ: tylna kamera pełnoekranowa + PiP ──

  Widget _buildCameraLayout() {
    return LayoutBuilder(builder: (context, constraints) {
      final screenW = constraints.maxWidth;
      final screenH = constraints.maxHeight;

      // PiP: 50% szerokości i 33% wysokości ekranu
      final pipW = screenW * 0.50;
      final pipH = screenH * 0.33;

      // Domyślna pozycja: prawy górny róg z marginesem 12 px
      if (!_pipOffsetSet) {
        _pipOffset = Offset(screenW - pipW - 12, 12);
        _pipOffsetSet = true;
      }

      return Stack(
        children: [
          // ── TŁO: kamera tylna (full screen) ──
          Positioned.fill(
            child: _buildFullPreview(_backCtrl!),
          ),

          // ── Gradient na dole pod przyciskami ──
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 160,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.85),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // ── Nagrywanie: timer na górze na środku ──
          if (_isRecording)
            Positioned(
              top: 48,
              left: 0,
              right: 0,
              child: Center(child: _buildRecTimer()),
            ),

          // ── Etykieta tylnej kamery (lewy górny) ──
          Positioned(
            top: 48,
            left: 14,
            child: _buildLabel('TYLNA', Icons.camera_rear),
          ),

          // ── PiP: przednia kamera (prawy górny) ── DRAGGABLE ──
          Positioned(
            left: _pipOffset.dx,
            top: _pipOffset.dy,
            child: GestureDetector(
              onPanUpdate: (d) {
                setState(() {
                  double nx = _pipOffset.dx + d.delta.dx;
                  double ny = _pipOffset.dy + d.delta.dy;
                  // Ogranicz do ekranu
                  nx = nx.clamp(0.0, screenW - pipW);
                  ny = ny.clamp(0.0, screenH - pipH);
                  _pipOffset = Offset(nx, ny);
                });
              },
              child: _buildPipWindow(pipW, pipH),
            ),
          ),

          // ── Przyciski na dole ──
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildControls(),
          ),
        ],
      );
    });
  }

  // ── Podgląd pełnoekranowy (tylna) ──
  Widget _buildFullPreview(CameraController ctrl) {
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: ctrl.value.previewSize?.height ?? 1,
            height: ctrl.value.previewSize?.width ?? 1,
            child: CameraPreview(ctrl),
          ),
        ),
      ),
    );
  }

  // ── Okienko PiP (przednia) ──
  Widget _buildPipWindow(double w, double h) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isRecording
              ? Colors.red.withOpacity(0.85)
              : Colors.white.withOpacity(0.55),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.6),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Podgląd przedniej kamery
            OverflowBox(
              alignment: Alignment.center,
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _frontCtrl!.value.previewSize?.height ?? 1,
                  height: _frontCtrl!.value.previewSize?.width ?? 1,
                  child: CameraPreview(_frontCtrl!),
                ),
              ),
            ),
            // Etykieta wewnątrz PiP
            Positioned(
              bottom: 7,
              left: 9,
              child: _buildLabel('PRZEDNIA', Icons.camera_front, small: true),
            ),
            // Czerwona kropka REC wewnątrz PiP
            if (_isRecording)
              Positioned(
                top: 9,
                right: 9,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: Colors.red.withOpacity(0.7),
                          blurRadius: 8,
                          spreadRadius: 2)
                    ],
                  ),
                ),
              ),
            // Flash overlay
            if (_isBusy && !_isRecording)
              Container(color: Colors.white.withOpacity(0.18)),
          ],
        ),
      ),
    );
  }

  // ── Etykieta ──
  Widget _buildLabel(String text, IconData icon, {bool small = false}) {
    final fs = small ? 10.0 : 12.0;
    final is_ = small ? 11.0 : 14.0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.50),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.amber, size: is_),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: fs,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1)),
        ],
      ),
    );
  }

  // ── Timer REC ──
  Widget _buildRecTimer() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.92),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.fiber_manual_record,
                color: Colors.white, size: 10),
            const SizedBox(width: 6),
            Text(
              'REC  ${_fmtTime(_recSeconds)}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1),
            ),
          ],
        ),
      );

  // ── Przyciski sterowania ──
  Widget _buildControls() => Padding(
        padding: const EdgeInsets.fromLTRB(28, 16, 28, 36),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildThumbnail(),
            _buildPhotoButton(),
            _buildVideoButton(),
          ],
        ),
      );

  Widget _buildThumbnail() => Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white38, width: 1.5),
          color: Colors.grey.shade900,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: _lastPhoto != null
              ? Image.file(_lastPhoto!, fit: BoxFit.cover)
              : const Icon(Icons.photo_library_outlined,
                  color: Colors.white30, size: 26),
        ),
      );

  Widget _buildPhotoButton() {
    final active = _initialized && !_isBusy && !_isRecording;
    return GestureDetector(
      onTap: active ? _takePhotos : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? Colors.white : Colors.grey.shade700,
              boxShadow: active
                  ? [
                      BoxShadow(
                          color: Colors.white.withOpacity(0.35),
                          blurRadius: 14)
                    ]
                  : [],
            ),
            child: Icon(Icons.camera_alt,
                color: active ? Colors.black : Colors.grey.shade500, size: 36),
          ),
          const SizedBox(height: 7),
          Text('ZDJĘCIA',
              style: TextStyle(
                  color: active ? Colors.white70 : Colors.grey.shade600,
                  fontSize: 10,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildVideoButton() {
    final active = _initialized && !_isBusy;
    return GestureDetector(
      onTap: active ? _toggleRecording : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: active ? Colors.red : Colors.grey.shade700, width: 3),
            ),
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: _isRecording ? 26 : 46,
                height: _isRecording ? 26 : 46,
                decoration: BoxDecoration(
                  color: active ? Colors.red : Colors.grey.shade700,
                  shape:
                      _isRecording ? BoxShape.rectangle : BoxShape.circle,
                  borderRadius: _isRecording ? BorderRadius.circular(6) : null,
                ),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            _isRecording ? 'STOP' : 'WIDEO',
            style: TextStyle(
                color: _isRecording
                    ? Colors.red
                    : active
                        ? Colors.white70
                        : Colors.grey.shade600,
                fontSize: 10,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // ── Ekrany pomocnicze ──

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.no_photography, color: Colors.red, size: 72),
              const SizedBox(height: 20),
              Text(_error!,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 16, height: 1.5),
                  textAlign: TextAlign.center),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _requestPermissionsAndInit,
                icon: const Icon(Icons.refresh),
                label: const Text('Spróbuj ponownie'),
              ),
            ],
          ),
        ),
      );

  Widget _buildLoading() => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.amber, strokeWidth: 3),
            SizedBox(height: 20),
            Text('Uruchamianie kamer…',
                style: TextStyle(color: Colors.white70, fontSize: 16)),
          ],
        ),
      );
}
