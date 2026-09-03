# Vet AI

Vet AI is a Flutter veterinary decision-support and smart animal-monitoring platform for **livestock, poultry and dogs**.

## V0.1 foundation

The current application foundation includes:

- Automatic device-locale resolution with versioned localization catalogs.
- First-run onboarding for owner/contact, company/farm, country/region, workers/veterinarians, barns, indoor area, animal groups/counts, breeds/age, production purpose, ventilation, vaccination and disease history.
- Subscription selection:
  - **Vet AI Software** — AI photo/video assessment, records, risk alerts, history and reports.
  - **Vet AI Smart Monitoring** — software features plus sensor telemetry and continuous anomaly monitoring.
  - Monthly or annual billing selection.
- Main dashboards for Livestock, Poultry and Dogs.
- AI Health Scan safety-first flow placeholder.
- Smart Monitoring dashboard with a hardware-neutral Sensor Gateway interface.
- Alert and longitudinal health-history foundations.
- Dark clinical UI direction matching the approved Vet AI concept.

## Smart Monitoring telemetry model

The Sensor Gateway is designed to accept real telemetry from collars, tags and barn gateways over BLE/Wi-Fi/MQTT without coupling the UI to one hardware vendor. Planned normalized signals include:

- Body temperature.
- Barn/room temperature and humidity.
- Accelerometer/IMU movement and activity.
- Steps and locomotion patterns.
- Lying/standing duration.
- Feeding and rumination duration where applicable.
- Distance from herd / isolation behavior / geofencing.
- Location where supported.
- Environmental and acoustic signals.
- Calving-related behavioral/temperature signals.

The repository currently uses a **DemoSensorGateway** only to exercise the live UI. No demo value is treated as a medical result.

## Safety model

Vet AI is being designed as veterinary **decision support**, not as an autonomous replacement for a veterinarian or laboratory testing. The product output model will distinguish:

- Observed visual/sensor signs.
- Risk level: red / orange / yellow / no current alert / insufficient data.
- Differential possibilities rather than forced single-disease labels.
- Isolation/biosecurity guidance when contagious disease cannot be excluded.
- Recommended veterinary or laboratory confirmation.
- AI suspicion vs veterinarian/laboratory-confirmed diagnosis.

A model must be able to return **insufficient data** rather than inventing a diagnosis.

## Localization

The app follows the phone locale automatically. Core catalogs are currently seeded for English, Arabic and Simplified Chinese, while the localization architecture already exposes a broad world-language locale list. Medical terminology should be translated and QA-reviewed in versioned catalogs before a language is declared production-complete; unsupported/missing strings currently fall back to English.

## Flutter / TestFlight

- Flutter package name: `app`
- iOS bundle identifier: `com.vetai.app`
- Codemagic workflow: `ios-release`
- Codemagic generates missing iOS/Android native projects, runs dependency install and static analysis, signs the iOS build and submits the IPA to TestFlight.

## Next engineering milestones

1. Authentication/backend and persisted farm profiles.
2. Production localization catalogs and translation QA workflow.
3. Camera/gallery permissions and real image/video upload.
4. Veterinary knowledge-base schema and evidence/versioning.
5. AI orchestration API with structured safety outputs.
6. Real sensor protocol adapters and device provisioning.
7. Baseline/anomaly engine per animal/flock.
8. Push notifications and emergency escalation.
9. Billing/subscription backend.
10. Validation datasets and per-condition performance reporting before medical claims.
