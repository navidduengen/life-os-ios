#!/usr/bin/env python3
"""Single source of the Apple Health type catalog.

Generates
  Packages/LifeOSKit/Sources/LifeOSKit/Health/HealthDataCatalog+Types.swift  (this repo)
  resources/js/modules/health/appleHealthTypes.ts                             (life-os-prototype, pass its path)

Usage: python3 scripts/health_types.py [path/to/life-os-prototype]
"""
import json, os, sys

GROUPS = [
    # id, label, SF Symbol
    ("activity", "Aktivität", "flame"),
    ("body", "Körpermaße", "figure"),
    ("heart", "Herz", "heart"),
    ("vitals", "Vitalwerte", "waveform.path.ecg"),
    ("respiratory", "Atmung", "lungs"),
    ("mobility", "Mobilität", "figure.walk"),
    ("nutrition", "Ernährung", "fork.knife"),
    ("sleep", "Schlaf", "bed.double"),
    ("mind", "Achtsamkeit & Psyche", "brain.head.profile"),
    ("hearing", "Hören", "ear"),
    ("environment", "Umgebung", "sun.max"),
    ("cycle", "Zyklus & Fortpflanzung", "drop"),
    ("symptoms", "Symptome", "bandage"),
    ("habits", "Gewohnheiten", "hands.sparkles"),
    ("workouts", "Trainings", "figure.run"),
    ("records", "Gesundheitsakten", "cross.case"),
    ("profile", "Profil", "person.text.rectangle"),
]

Q = "HKQuantityTypeIdentifier"
C = "HKCategoryTypeIdentifier"

# (identifier suffix, group, label, aggregation)  aggregation: sum | avg
QUANTITY = [
    ("StepCount", "activity", "Schritte", "sum"),
    ("DistanceWalkingRunning", "activity", "Strecke Gehen und Laufen", "sum"),
    ("DistanceCycling", "activity", "Strecke Radfahren", "sum"),
    ("DistanceSwimming", "activity", "Strecke Schwimmen", "sum"),
    ("DistanceWheelchair", "activity", "Strecke Rollstuhl", "sum"),
    ("DistanceDownhillSnowSports", "activity", "Strecke Wintersport", "sum"),
    ("DistanceCrossCountrySkiing", "activity", "Strecke Langlauf", "sum"),
    ("DistancePaddleSports", "activity", "Strecke Paddeln", "sum"),
    ("DistanceRowing", "activity", "Strecke Rudern", "sum"),
    ("DistanceSkatingSports", "activity", "Strecke Skaten", "sum"),
    ("PushCount", "activity", "Rollstuhl-Anschübe", "sum"),
    ("SwimmingStrokeCount", "activity", "Schwimmzüge", "sum"),
    ("FlightsClimbed", "activity", "Etagen gestiegen", "sum"),
    ("NikeFuel", "activity", "NikeFuel", "sum"),
    ("AppleExerciseTime", "activity", "Trainingsminuten", "sum"),
    ("AppleMoveTime", "activity", "Bewegungsminuten", "sum"),
    ("AppleStandTime", "activity", "Stehminuten", "sum"),
    ("ActiveEnergyBurned", "activity", "Aktive Energie", "sum"),
    ("BasalEnergyBurned", "activity", "Ruheenergie", "sum"),
    ("PhysicalEffort", "activity", "Körperliche Anstrengung", "avg"),
    ("WorkoutEffortScore", "activity", "Trainingsintensität", "avg"),
    ("EstimatedWorkoutEffortScore", "activity", "Geschätzte Trainingsintensität", "avg"),
    ("CyclingCadence", "activity", "Trittfrequenz", "avg"),
    ("CyclingPower", "activity", "Radleistung", "avg"),
    ("CyclingFunctionalThresholdPower", "activity", "Funktionelle Schwellenleistung", "avg"),
    ("CyclingSpeed", "activity", "Geschwindigkeit Radfahren", "avg"),
    ("RunningPower", "activity", "Laufleistung", "avg"),
    ("RunningSpeed", "activity", "Laufgeschwindigkeit", "avg"),
    ("RunningStrideLength", "activity", "Schrittlänge beim Laufen", "avg"),
    ("RunningVerticalOscillation", "activity", "Vertikale Bewegung beim Laufen", "avg"),
    ("RunningGroundContactTime", "activity", "Bodenkontaktzeit", "avg"),
    ("CrossCountrySkiingSpeed", "activity", "Geschwindigkeit Langlauf", "avg"),
    ("PaddleSportsSpeed", "activity", "Geschwindigkeit Paddeln", "avg"),
    ("RowingSpeed", "activity", "Geschwindigkeit Rudern", "avg"),
    ("UnderwaterDepth", "activity", "Tauchtiefe", "avg"),
    ("WaterTemperature", "environment", "Wassertemperatur", "avg"),
    ("Height", "body", "Größe", "avg"),
    ("BodyMass", "body", "Gewicht", "avg"),
    ("BodyMassIndex", "body", "Body-Mass-Index", "avg"),
    ("LeanBodyMass", "body", "Fettfreie Körpermasse", "avg"),
    ("BodyFatPercentage", "body", "Körperfettanteil", "avg"),
    ("WaistCircumference", "body", "Taillenumfang", "avg"),
    ("BodyTemperature", "body", "Körpertemperatur", "avg"),
    ("BasalBodyTemperature", "cycle", "Basaltemperatur", "avg"),
    ("AppleSleepingWristTemperature", "sleep", "Handgelenktemperatur im Schlaf", "avg"),
    ("HeartRate", "heart", "Herzfrequenz", "avg"),
    ("RestingHeartRate", "heart", "Ruhepuls", "avg"),
    ("WalkingHeartRateAverage", "heart", "Durchschnittspuls beim Gehen", "avg"),
    ("HeartRateVariabilitySDNN", "heart", "Herzfrequenzvariabilität", "avg"),
    ("HeartRateRecoveryOneMinute", "heart", "Herzfrequenzerholung", "avg"),
    ("AtrialFibrillationBurden", "heart", "Vorhofflimmern-Anteil", "avg"),
    ("VO2Max", "heart", "Cardiofitness (VO₂max)", "avg"),
    ("PeripheralPerfusionIndex", "heart", "Perfusionsindex", "avg"),
    ("BloodPressureSystolic", "vitals", "Blutdruck systolisch", "avg"),
    ("BloodPressureDiastolic", "vitals", "Blutdruck diastolisch", "avg"),
    ("OxygenSaturation", "vitals", "Sauerstoffsättigung", "avg"),
    ("BloodGlucose", "vitals", "Blutzucker", "avg"),
    ("ElectrodermalActivity", "vitals", "Elektrodermale Aktivität", "avg"),
    ("InsulinDelivery", "vitals", "Insulin", "sum"),
    ("BloodAlcoholContent", "vitals", "Blutalkohol", "avg"),
    ("NumberOfAlcoholicBeverages", "vitals", "Alkoholische Getränke", "sum"),
    ("NumberOfTimesFallen", "vitals", "Stürze", "sum"),
    ("RespiratoryRate", "respiratory", "Atemfrequenz", "avg"),
    ("AppleSleepingBreathingDisturbances", "respiratory", "Atemstörungen im Schlaf", "avg"),
    ("InhalerUsage", "respiratory", "Inhalator-Nutzung", "sum"),
    ("ForcedVitalCapacity", "respiratory", "Forcierte Vitalkapazität", "avg"),
    ("ForcedExpiratoryVolume1", "respiratory", "Einsekundenkapazität (FEV1)", "avg"),
    ("PeakExpiratoryFlowRate", "respiratory", "Spitzenfluss", "avg"),
    ("WalkingSpeed", "mobility", "Gehgeschwindigkeit", "avg"),
    ("WalkingStepLength", "mobility", "Schrittlänge", "avg"),
    ("WalkingAsymmetryPercentage", "mobility", "Gang-Asymmetrie", "avg"),
    ("WalkingDoubleSupportPercentage", "mobility", "Doppelschrittphase", "avg"),
    ("StairAscentSpeed", "mobility", "Treppensteigen aufwärts", "avg"),
    ("StairDescentSpeed", "mobility", "Treppensteigen abwärts", "avg"),
    ("SixMinuteWalkTestDistance", "mobility", "6-Minuten-Gehtest", "avg"),
    ("AppleWalkingSteadiness", "mobility", "Gangstabilität", "avg"),
    ("EnvironmentalAudioExposure", "hearing", "Umgebungslautstärke", "avg"),
    ("HeadphoneAudioExposure", "hearing", "Kopfhörerlautstärke", "avg"),
    ("EnvironmentalSoundReduction", "hearing", "Lärmreduzierung", "avg"),
    ("UVExposure", "environment", "UV-Belastung", "avg"),
    ("TimeInDaylight", "environment", "Zeit bei Tageslicht", "sum"),
    ("DietaryEnergyConsumed", "nutrition", "Energie (Nahrung)", "sum"),
    ("DietaryProtein", "nutrition", "Eiweiß", "sum"),
    ("DietaryCarbohydrates", "nutrition", "Kohlenhydrate", "sum"),
    ("DietaryFatTotal", "nutrition", "Fett gesamt", "sum"),
    ("DietaryFatSaturated", "nutrition", "Gesättigte Fettsäuren", "sum"),
    ("DietaryFatMonounsaturated", "nutrition", "Einfach ungesättigte Fettsäuren", "sum"),
    ("DietaryFatPolyunsaturated", "nutrition", "Mehrfach ungesättigte Fettsäuren", "sum"),
    ("DietaryCholesterol", "nutrition", "Cholesterin", "sum"),
    ("DietaryFiber", "nutrition", "Ballaststoffe", "sum"),
    ("DietarySugar", "nutrition", "Zucker", "sum"),
    ("DietaryWater", "nutrition", "Wasser", "sum"),
    ("DietaryCaffeine", "nutrition", "Koffein", "sum"),
    ("DietarySodium", "nutrition", "Natrium", "sum"),
    ("DietaryPotassium", "nutrition", "Kalium", "sum"),
    ("DietaryCalcium", "nutrition", "Calcium", "sum"),
    ("DietaryIron", "nutrition", "Eisen", "sum"),
    ("DietaryMagnesium", "nutrition", "Magnesium", "sum"),
    ("DietaryPhosphorus", "nutrition", "Phosphor", "sum"),
    ("DietaryZinc", "nutrition", "Zink", "sum"),
    ("DietaryCopper", "nutrition", "Kupfer", "sum"),
    ("DietaryManganese", "nutrition", "Mangan", "sum"),
    ("DietarySelenium", "nutrition", "Selen", "sum"),
    ("DietaryChromium", "nutrition", "Chrom", "sum"),
    ("DietaryMolybdenum", "nutrition", "Molybdän", "sum"),
    ("DietaryChloride", "nutrition", "Chlorid", "sum"),
    ("DietaryIodine", "nutrition", "Jod", "sum"),
    ("DietaryVitaminA", "nutrition", "Vitamin A", "sum"),
    ("DietaryVitaminB6", "nutrition", "Vitamin B6", "sum"),
    ("DietaryVitaminB12", "nutrition", "Vitamin B12", "sum"),
    ("DietaryVitaminC", "nutrition", "Vitamin C", "sum"),
    ("DietaryVitaminD", "nutrition", "Vitamin D", "sum"),
    ("DietaryVitaminE", "nutrition", "Vitamin E", "sum"),
    ("DietaryVitaminK", "nutrition", "Vitamin K", "sum"),
    ("DietaryThiamin", "nutrition", "Thiamin (B1)", "sum"),
    ("DietaryRiboflavin", "nutrition", "Riboflavin (B2)", "sum"),
    ("DietaryNiacin", "nutrition", "Niacin (B3)", "sum"),
    ("DietaryPantothenicAcid", "nutrition", "Pantothensäure (B5)", "sum"),
    ("DietaryBiotin", "nutrition", "Biotin", "sum"),
    ("DietaryFolate", "nutrition", "Folat", "sum"),
]

# (identifier suffix, group, label)
CATEGORY = [
    ("SleepAnalysis", "sleep", "Schlafanalyse"),
    ("SleepApneaEvent", "sleep", "Atemaussetzer im Schlaf"),
    ("MindfulSession", "mind", "Achtsamkeitsminuten"),
    ("AppleStandHour", "activity", "Stehstunden"),
    ("HighHeartRateEvent", "heart", "Hohe Herzfrequenz"),
    ("LowHeartRateEvent", "heart", "Niedrige Herzfrequenz"),
    ("IrregularHeartRhythmEvent", "heart", "Unregelmäßiger Herzrhythmus"),
    ("LowCardioFitnessEvent", "heart", "Niedrige Cardiofitness"),
    ("EnvironmentalAudioExposureEvent", "hearing", "Laute Umgebung"),
    ("HeadphoneAudioExposureEvent", "hearing", "Laute Kopfhörer"),
    ("AppleWalkingSteadinessEvent", "mobility", "Gangstabilität-Hinweis"),
    ("ToothbrushingEvent", "habits", "Zähneputzen"),
    ("HandwashingEvent", "habits", "Händewaschen"),
    ("MenstrualFlow", "cycle", "Periode"),
    ("IntermenstrualBleeding", "cycle", "Zwischenblutung"),
    ("InfrequentMenstrualCycles", "cycle", "Seltene Zyklen"),
    ("IrregularMenstrualCycles", "cycle", "Unregelmäßige Zyklen"),
    ("PersistentIntermenstrualBleeding", "cycle", "Anhaltende Zwischenblutungen"),
    ("ProlongedMenstrualPeriods", "cycle", "Verlängerte Periode"),
    ("OvulationTestResult", "cycle", "Ovulationstest"),
    ("CervicalMucusQuality", "cycle", "Zervixschleim"),
    ("SexualActivity", "cycle", "Sexuelle Aktivität"),
    ("Pregnancy", "cycle", "Schwangerschaft"),
    ("PregnancyTestResult", "cycle", "Schwangerschaftstest"),
    ("ProgesteroneTestResult", "cycle", "Progesterontest"),
    ("Lactation", "cycle", "Stillzeit"),
    ("Contraceptive", "cycle", "Verhütung"),
    ("BleedingDuringPregnancy", "cycle", "Blutung in der Schwangerschaft"),
    ("BleedingAfterPregnancy", "cycle", "Blutung nach der Schwangerschaft"),
    ("AbdominalCramps", "symptoms", "Bauchkrämpfe"),
    ("Acne", "symptoms", "Akne"),
    ("AppetiteChanges", "symptoms", "Appetitveränderung"),
    ("BladderIncontinence", "symptoms", "Blasenschwäche"),
    ("Bloating", "symptoms", "Blähungen"),
    ("BreastPain", "symptoms", "Brustschmerzen"),
    ("ChestTightnessOrPain", "symptoms", "Engegefühl oder Schmerz in der Brust"),
    ("Chills", "symptoms", "Schüttelfrost"),
    ("Constipation", "symptoms", "Verstopfung"),
    ("Coughing", "symptoms", "Husten"),
    ("Diarrhea", "symptoms", "Durchfall"),
    ("Dizziness", "symptoms", "Schwindel"),
    ("DrySkin", "symptoms", "Trockene Haut"),
    ("Fainting", "symptoms", "Ohnmacht"),
    ("Fatigue", "symptoms", "Müdigkeit"),
    ("Fever", "symptoms", "Fieber"),
    ("GeneralizedBodyAche", "symptoms", "Gliederschmerzen"),
    ("HairLoss", "symptoms", "Haarausfall"),
    ("Headache", "symptoms", "Kopfschmerzen"),
    ("Heartburn", "symptoms", "Sodbrennen"),
    ("HotFlashes", "symptoms", "Hitzewallungen"),
    ("LossOfSmell", "symptoms", "Geruchsverlust"),
    ("LossOfTaste", "symptoms", "Geschmacksverlust"),
    ("LowerBackPain", "symptoms", "Rückenschmerzen unten"),
    ("MemoryLapse", "symptoms", "Vergesslichkeit"),
    ("MoodChanges", "symptoms", "Stimmungsschwankungen"),
    ("Nausea", "symptoms", "Übelkeit"),
    ("NightSweats", "symptoms", "Nachtschweiß"),
    ("PelvicPain", "symptoms", "Beckenschmerzen"),
    ("RapidPoundingOrFlutteringHeartbeat", "symptoms", "Herzrasen oder -klopfen"),
    ("RunnyNose", "symptoms", "Laufende Nase"),
    ("ShortnessOfBreath", "symptoms", "Kurzatmigkeit"),
    ("SinusCongestion", "symptoms", "Verstopfte Nebenhöhlen"),
    ("SkippedHeartbeat", "symptoms", "Herzstolpern"),
    ("SleepChanges", "symptoms", "Schlafveränderungen"),
    ("SoreThroat", "symptoms", "Halsschmerzen"),
    ("VaginalDryness", "symptoms", "Scheidentrockenheit"),
    ("Vomiting", "symptoms", "Erbrechen"),
    ("Wheezing", "symptoms", "Pfeifende Atmung"),
]

# (identifier, kind, group, label)
SPECIAL = [
    ("HKWorkoutTypeIdentifier", "workout", "workouts", "Trainings"),
    ("HKDataTypeIdentifierElectrocardiogram", "ecg", "heart", "EKG"),
    ("HKDataTypeIdentifierAudiogram", "audiogram", "hearing", "Hörtest (Audiogramm)"),
    ("HKDataTypeStateOfMind", "stateOfMind", "mind", "Gemütszustand"),
    ("HKClinicalTypeIdentifierAllergyRecord", "clinical", "records", "Allergien"),
    ("HKClinicalTypeIdentifierClinicalNoteRecord", "clinical", "records", "Arztberichte"),
    ("HKClinicalTypeIdentifierConditionRecord", "clinical", "records", "Erkrankungen"),
    ("HKClinicalTypeIdentifierImmunizationRecord", "clinical", "records", "Impfungen"),
    ("HKClinicalTypeIdentifierLabResultRecord", "clinical", "records", "Laborergebnisse"),
    ("HKClinicalTypeIdentifierMedicationRecord", "clinical", "records", "Medikamente"),
    ("HKClinicalTypeIdentifierProcedureRecord", "clinical", "records", "Behandlungen"),
    ("HKClinicalTypeIdentifierVitalSignRecord", "clinical", "records", "Vitalzeichen (Akte)"),
    ("HKClinicalTypeIdentifierCoverageRecord", "clinical", "records", "Versicherung"),
    ("HKCharacteristicTypeIdentifierDateOfBirth", "characteristic", "profile", "Geburtsdatum"),
    ("HKCharacteristicTypeIdentifierBiologicalSex", "characteristic", "profile", "Biologisches Geschlecht"),
    ("HKCharacteristicTypeIdentifierBloodType", "characteristic", "profile", "Blutgruppe"),
    ("HKCharacteristicTypeIdentifierFitzpatrickSkinType", "characteristic", "profile", "Hauttyp"),
    ("HKCharacteristicTypeIdentifierWheelchairUse", "characteristic", "profile", "Rollstuhlnutzung"),
    ("HKCharacteristicTypeIdentifierActivityMoveMode", "characteristic", "profile", "Bewegungsziel-Art"),
]

def types():
    out = []
    for suffix, group, label, agg in QUANTITY:
        out.append({"id": Q + suffix, "kind": "quantity", "group": group, "label": label, "aggregation": agg})
    for suffix, group, label in CATEGORY:
        out.append({"id": C + suffix, "kind": "category", "group": group, "label": label, "aggregation": "count"})
    for ident, kind, group, label in SPECIAL:
        out.append({"id": ident, "kind": kind, "group": group, "label": label, "aggregation": "count"})
    ids = [t["id"] for t in out]
    assert len(ids) == len(set(ids)), "duplicate identifiers"
    groups = {g[0] for g in GROUPS}
    assert all(t["group"] in groups for t in out)
    return out

def swift_string(s):
    return json.dumps(s, ensure_ascii=False)

def write_swift(path):
    lines = [
        "// Generated by scripts/health_types.py. Do not edit by hand.",
        "",
        "extension HealthDataGroup {",
        "    public static let ordered: [HealthDataGroup] = [",
    ]
    lines += [f"        .{g[0]}," for g in GROUPS]
    lines += ["    ]", "", "    public var label: String {", "        switch self {"]
    lines += [f"        case .{g[0]}: {swift_string(g[1])}" for g in GROUPS]
    lines += ["        }", "    }", "", "    public var symbol: String {", "        switch self {"]
    lines += [f"        case .{g[0]}: {swift_string(g[2])}" for g in GROUPS]
    lines += ["        }", "    }", "}", "", "extension HealthDataCatalog {", "    public static let all: [HealthDataType] = ["]
    for t in types():
        lines.append(f"        HealthDataType(id: {swift_string(t['id'])}, kind: .{t['kind']}, group: .{t['group']}, label: {swift_string(t['label'])}, aggregation: .{t['aggregation']}),")
    lines += ["    ]", "}", ""]
    open(path, "w").write("\n".join(lines))

def write_ts(path):
    body = [
        "// Generated by scripts/health_types.py in navidduengen/life-os-ios. Do not edit by hand.",
        "",
        "export type AppleHealthKind = 'quantity' | 'category' | 'workout' | 'ecg' | 'audiogram' | 'stateOfMind' | 'clinical' | 'characteristic'",
        "export type AppleHealthAggregation = 'sum' | 'avg' | 'count'",
        "",
        "export interface AppleHealthGroup {",
        "  id: string",
        "  label: string",
        "}",
        "",
        "export interface AppleHealthType {",
        "  id: string",
        "  kind: AppleHealthKind",
        "  group: string",
        "  label: string",
        "  aggregation: AppleHealthAggregation",
        "}",
        "",
        "export const APPLE_HEALTH_GROUPS: AppleHealthGroup[] = [",
    ]
    body += [f"  {{ id: '{g[0]}', label: '{g[1]}' }}," for g in GROUPS]
    body += ["]", "", "export const APPLE_HEALTH_TYPES: AppleHealthType[] = ["]
    body += [f"  {{ id: '{t['id']}', kind: '{t['kind']}', group: '{t['group']}', label: '{t['label']}', aggregation: '{t['aggregation']}' }}," for t in types()]
    body += ["]", ""]
    open(path, "w").write("\n".join(body))

if __name__ == "__main__":
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    write_swift(os.path.join(root, "Packages/LifeOSKit/Sources/LifeOSKit/Health/HealthDataCatalog+Types.swift"))
    if len(sys.argv) > 1:
        write_ts(os.path.join(sys.argv[1], "resources/js/modules/health/appleHealthTypes.ts"))
    print(len(types()), "types")
