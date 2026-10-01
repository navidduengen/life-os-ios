#if canImport(HealthKit) && !targetEnvironment(macCatalyst)
import Foundation
import HealthKit
import LifeOSKit

/// German texts for HealthKit enum values, stored next to the raw number so
/// the web view can show them without knowing HealthKit.
enum HealthLabels {
    static func categoryValue(_ value: Int, type: String) -> String? {
        switch type {
        case HKCategoryTypeIdentifier.sleepAnalysis.rawValue:
            switch HKCategoryValueSleepAnalysis(rawValue: value) {
            case .inBed: return "Im Bett"
            case .asleepUnspecified: return "Schlaf"
            case .awake: return "Wach"
            case .asleepCore: return "Kernschlaf"
            case .asleepDeep: return "Tiefschlaf"
            case .asleepREM: return "REM-Schlaf"
            default: return nil
            }
        case HKCategoryTypeIdentifier.appleStandHour.rawValue:
            return value == HKCategoryValueAppleStandHour.stood.rawValue ? "Gestanden" : "Nicht gestanden"
        case HKCategoryTypeIdentifier.menstrualFlow.rawValue:
            guard let flow = HKCategoryValueMenstrualFlow(rawValue: value) else { return nil }
            switch flow {
            case .light: return "Leicht"
            case .medium: return "Mittel"
            case .heavy: return "Stark"
            case .none: return "Keine"
            default: return "Nicht angegeben"
            }
        case HKCategoryTypeIdentifier.ovulationTestResult.rawValue:
            switch HKCategoryValueOvulationTestResult(rawValue: value) {
            case .negative: return "Negativ"
            case .luteinizingHormoneSurge: return "LH-Anstieg"
            case .estrogenSurge: return "Östrogenanstieg"
            case .indeterminate: return "Unklar"
            default: return nil
            }
        case HKCategoryTypeIdentifier.pregnancyTestResult.rawValue, HKCategoryTypeIdentifier.progesteroneTestResult.rawValue:
            switch HKCategoryValuePregnancyTestResult(rawValue: value) {
            case .negative: return "Negativ"
            case .positive: return "Positiv"
            case .indeterminate: return "Unklar"
            default: return nil
            }
        case HKCategoryTypeIdentifier.cervicalMucusQuality.rawValue:
            switch HKCategoryValueCervicalMucusQuality(rawValue: value) {
            case .dry: return "Trocken"
            case .sticky: return "Klebrig"
            case .creamy: return "Cremig"
            case .watery: return "Wässrig"
            case .eggWhite: return "Spinnbar"
            default: return nil
            }
        case HKCategoryTypeIdentifier.appetiteChanges.rawValue:
            switch HKCategoryValueAppetiteChanges(rawValue: value) {
            case .noChange: return "Keine Veränderung"
            case .decreased: return "Weniger"
            case .increased: return "Mehr"
            default: return "Nicht angegeben"
            }
        case HKCategoryTypeIdentifier.contraceptive.rawValue:
            switch HKCategoryValueContraceptive(rawValue: value) {
            case .implant: return "Implantat"
            case .injection: return "Spritze"
            case .intrauterineDevice: return "Spirale"
            case .intravaginalRing: return "Vaginalring"
            case .oral: return "Pille"
            case .patch: return "Pflaster"
            default: return "Nicht angegeben"
            }
        case HKCategoryTypeIdentifier.environmentalAudioExposureEvent.rawValue,
             HKCategoryTypeIdentifier.headphoneAudioExposureEvent.rawValue:
            return "Grenzwert überschritten"
        default:
            if HealthDataCatalog.type(type)?.group == .symptoms {
                switch HKCategoryValueSeverity(rawValue: value) {
                case .notPresent: return "Nicht vorhanden"
                case .mild: return "Leicht"
                case .moderate: return "Mittel"
                case .severe: return "Stark"
                default: return "Vorhanden"
                }
            }
            return nil
        }
    }

    static func workoutActivity(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: "Laufen"
        case .walking: "Gehen"
        case .hiking: "Wandern"
        case .cycling: "Radfahren"
        case .swimming: "Schwimmen"
        case .traditionalStrengthTraining: "Krafttraining"
        case .functionalStrengthTraining: "Funktionelles Krafttraining"
        case .highIntensityIntervalTraining: "HIIT"
        case .yoga: "Yoga"
        case .pilates: "Pilates"
        case .dance, .socialDance, .cardioDance: "Tanzen"
        case .elliptical: "Crosstrainer"
        case .rowing: "Rudern"
        case .stairClimbing, .stairs, .stepTraining: "Treppensteigen"
        case .coreTraining: "Core-Training"
        case .flexibility: "Beweglichkeit"
        case .cooldown: "Cool-down"
        case .mixedCardio: "Gemischtes Cardio"
        case .soccer: "Fußball"
        case .basketball: "Basketball"
        case .tennis: "Tennis"
        case .tableTennis: "Tischtennis"
        case .badminton: "Badminton"
        case .volleyball: "Volleyball"
        case .handball: "Handball"
        case .climbing: "Klettern"
        case .boxing, .kickboxing: "Boxen"
        case .martialArts: "Kampfsport"
        case .golf: "Golf"
        case .skatingSports: "Skaten"
        case .downhillSkiing: "Ski alpin"
        case .crossCountrySkiing: "Langlauf"
        case .snowboarding: "Snowboarden"
        case .paddleSports: "Paddeln"
        case .surfingSports: "Surfen"
        case .waterSports: "Wassersport"
        case .equestrianSports: "Reiten"
        case .mindAndBody: "Körper und Geist"
        case .wheelchairWalkPace, .wheelchairRunPace: "Rollstuhl"
        case .handCycling: "Handbike"
        case .swimBikeRun: "Triathlon"
        case .preparationAndRecovery: "Regeneration"
        default: "Training"
        }
    }

    static func ecgClassification(_ classification: HKElectrocardiogram.Classification) -> String {
        switch classification {
        case .sinusRhythm: "Sinusrhythmus"
        case .atrialFibrillation: "Vorhofflimmern"
        case .inconclusiveLowHeartRate: "Nicht eindeutig: niedrige Herzfrequenz"
        case .inconclusiveHighHeartRate: "Nicht eindeutig: hohe Herzfrequenz"
        case .inconclusivePoorReading: "Nicht eindeutig: schlechte Aufnahme"
        case .inconclusiveOther: "Nicht eindeutig"
        case .unrecognized: "Nicht erkannt"
        default: "Nicht ausgewertet"
        }
    }

    static func biologicalSex(_ sex: HKBiologicalSex) -> String {
        switch sex {
        case .female: "Weiblich"
        case .male: "Männlich"
        case .other: "Divers"
        default: "Nicht angegeben"
        }
    }

    static func bloodType(_ type: HKBloodType) -> String {
        switch type {
        case .aPositive: "A+"
        case .aNegative: "A−"
        case .bPositive: "B+"
        case .bNegative: "B−"
        case .abPositive: "AB+"
        case .abNegative: "AB−"
        case .oPositive: "0+"
        case .oNegative: "0−"
        default: "Nicht angegeben"
        }
    }

    static func localDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

#endif
