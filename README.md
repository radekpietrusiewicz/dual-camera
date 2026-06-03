# 📷 Dual Camera — Aplikacja Flutter

Aplikacja uruchamia **kamerę tylną i przednią jednocześnie**, pozwala robić zdjęcia oraz nagrywać wideo z obu kamer naraz. Pliki trafiają automatycznie do albumu **DualCamera** w galerii telefonu.

---

## Funkcje

| Funkcja | Opis |
|---|---|
| 📸 Zdjęcia | Oba aparaty strzelają równocześnie — jedno naciśnięcie, dwa zdjęcia |
| 🎬 Nagrywanie | Start/Stop nagrywa wideo z obu kamer jednocześnie |
| 🗂 Galeria | Pliki zapisywane w albumie `DualCamera` na urządzeniu |
| ⏱ Timer | Licznik czasu nagrywania w czasie rzeczywistym |
| 🖼 Miniatura | Podgląd ostatniego zdjęcia w lewym dolnym rogu |

---

## Wymagania systemowe

- **Android:** 5.0+ (API 21), zalecane Android 9+
- **iOS:** 13.0+, zalecane iPhone XS lub nowszy (dla jednoczesnego dual camera)
- Flutter SDK **3.10+**

---

## Instalacja i uruchomienie

### 1. Zainstaluj Flutter
Pobierz z https://flutter.dev/docs/get-started/install

### 2. Pobierz zależności
```bash
cd dual_camera_app
flutter pub get
```

### 3. Uruchom na urządzeniu
```bash
# Android
flutter run

# iOS (wymaga macOS + Xcode)
cd ios && pod install && cd ..
flutter run
```

### 4. Zbuduj APK (Android)
```bash
flutter build apk --release
# Plik: build/app/outputs/flutter-apk/app-release.apk
```

### 5. Zbuduj IPA (iOS)
```bash
flutter build ios --release
# Otwórz Xcode i wykonaj Archive
```

---

## Struktura projektu

```
lib/
├── main.dart                    # Punkt wejścia, inicjalizacja kamer
└── screens/
    └── dual_camera_screen.dart  # Główny ekran aplikacji
android/
└── app/src/main/AndroidManifest.xml  # Uprawnienia Android
ios/
└── Runner/Info.plist            # Uprawnienia iOS
```

---

## Uwagi techniczne

- Aplikacja korzysta z pakietu **`camera`** do sterowania kamerami
- Zdjęcia i wideo zapisywane są przez pakiet **`gal`** do galerii systemowej
- Na iOS jednoczesna praca obu kamer wymaga **AVCaptureMultiCamSession** (iPhone XS / A12 lub nowszy)
- Na Androidzie obsługa zależy od producenta i sterowników urządzenia — testowane na Pixel i Samsung Galaxy S-series

---

## Uprawnienia

| Uprawnienie | Cel |
|---|---|
| `CAMERA` | Dostęp do obu kamer |
| `RECORD_AUDIO` | Nagrywanie dźwięku podczas wideo |
| `READ/WRITE_EXTERNAL_STORAGE` | Zapis do galerii (Android ≤ 12) |
| `READ_MEDIA_IMAGES/VIDEO` | Zapis do galerii (Android 13+) |
| `NSCameraUsageDescription` | Dostęp do kamery (iOS) |
| `NSMicrophoneUsageDescription` | Dostęp do mikrofonu (iOS) |
| `NSPhotoLibraryAddUsageDescription` | Zapis zdjęć/wideo do galerii (iOS) |
