<p align="center"><img src="docs/icon-preview.png" width="120" alt="KolaCare icon"></p>

# KolaCare — AI leaf doctor for Sri Lankan farmers

**SE4041 Mobile Application Design and Development · Assignment 2 · Part A**
G M H Himal · IT23152632 · SLIIT Faculty of Computing

KolaCare (*kola* / කොළ = "leaf" in Sinhala) lets smallholder farmers and home gardeners
photograph a sick leaf and get an on-device diagnosis, an objective severity score,
a step-by-step treatment plan and weather-driven early warnings — in English, Sinhala
and Tamil, offline-first.

## Features

| Area | What it does | Key frameworks |
|---|---|---|
| **Scan** | Camera / photo library / sample leaves → Vision subject lifting → pixel-level symptom measurement → CoreML disease classifier | Vision, CoreML, Core Image, ImageIO, PhotosUI |
| **Diagnosis** | Disease name, confidence, % leaf area affected, lesion-map overlay (pinch/drag/double-tap zoom), photo-quality warnings, alternatives | SwiftUI gestures, custom modifiers |
| **Garden** | Plants with photos, crops, plots, GPS, scan history timeline, health trend chart, treatment checklists | SwiftData, Swift Charts |
| **Weather risk** | Open-Meteo hourly forecast → favourable-hours disease risk model per crop; offline cache | URLSession async/await, Codable |
| **Field map** | Health-coloured pins, contagion "spread zones", satellite view, tap-to-place plots | MapKit for SwiftUI, Core Location |
| **Library** | 26 diseases/pests with symptoms, organic vs chemical treatment, prevention, DOA 1920 hotline | Searchable lists, ShareLink |
| **Reminders** | Follow-up "re-scan" notifications that deep-link to the plant | UserNotifications |
| **Polish** | 3 colour themes, Dark Mode, Dynamic Type, VoiceOver, Reduce Motion, TipKit, haptics, iPad layouts, EN/SI/TA | String Catalog, TipKit, SensoryFeedback |

## Requirements

* Xcode 16 or later (the project uses folder-synchronised groups, project format 77)
* iOS 17.0+ deployment target; tested layouts for iPhone and iPad, portrait and landscape
* No third-party dependencies, no API keys

## Build & run

1. Open `KolaCare.xcodeproj`.
2. Select the **KolaCare** scheme and an iPhone simulator (e.g. iPhone 16).
3. *(Device only)* Set your team under *Signing & Capabilities*.
4. Press **⌘R**. On first launch, complete onboarding, then use **Settings › Load demo garden**
   (or the button on Home) to explore with sample data.
5. In the Simulator use **Scan › Try a sample** (there is no camera).

**Enable the CoreML model:** follow [`ModelTraining/README.md`](ModelTraining/README.md) to train
`LeafDoctor.mlmodel` with Create ML and drag it into `KolaCare/Resources`. Without it, the app
transparently uses on-device colour analysis.

**Tests:** **⌘U** runs unit tests (`KolaCareTests`) and UI tests (`KolaCareUITests`) with code coverage.

> If your Xcode cannot open the project, install [XcodeGen](https://github.com/yonaskolb/XcodeGen)
> and run `xcodegen` in this folder — `project.yml` describes the same targets.

## Architecture

MVVM with a thin service layer and dependency injection through initialisers and the SwiftUI environment.

```
KolaCare/
├── App/            entry point, root/tab navigation, router, settings keys, previews
├── Models/         SwiftData entities (Plant, ScanRecord) + value types (Disease, Severity, WeatherForecast…)
├── Services/       diagnosis pipeline, pixel analyser, weather networking + cache, risk engine,
│                   persistence, repository, location, notifications, demo data, logging
├── ViewModels/     ScanViewModel, DashboardViewModel (@Observable, @MainActor)
├── DesignSystem/   theme, custom modifiers (card, shimmer, staggered reveal, zoom transition), components
├── Views/          Onboarding, Dashboard, Scan, Garden, Map, Library, Settings
└── Resources/      Assets (icon, brand mark, sample leaves), diseases.json, Localizable.xcstrings, privacy manifest
KolaCareTests/      unit, integration and performance tests (XCTest)
KolaCareUITests/    end-to-end UI tests and launch-time measurement
ModelTraining/      Create ML training script + dataset preparation
docs/               user guide, AI usage log
```

## Privacy

Photos are analysed on the device and never uploaded. The only network call is the
anonymous weather request (latitude/longitude rounded to 4 decimals). A privacy manifest
(`PrivacyInfo.xcprivacy`) declares no tracking and no collected data.

## Credits

Weather: [Open-Meteo](https://open-meteo.com/) (CC BY 4.0). Training data: PlantVillage (CC BY-SA 4.0).
Agronomic content summarised from general extension guidance; always follow product labels and
Department of Agriculture (DOA) recommendations. AI assistance is documented in [`docs/AI_USAGE.md`](docs/AI_USAGE.md).
