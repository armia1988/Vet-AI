import 'package:flutter/material.dart';

class VetAnimalSpecies {
  const VetAnimalSpecies({
    required this.code,
    required this.group,
    required this.en,
    required this.ar,
    required this.nl,
    required this.icon,
    required this.emoji,
    this.diseaseScopeAliases = const [],
  });

  final String code;
  final String group;
  final String en;
  final String ar;
  final String nl;
  final IconData icon;
  final String emoji;
  final List<String> diseaseScopeAliases;
}

class VetDogBreed {
  const VetDogBreed({required this.code, required this.en, required this.ar, required this.nl});
  final String code;
  final String en;
  final String ar;
  final String nl;
}

const vetLivestockSpecies = <VetAnimalSpecies>[
  VetAnimalSpecies(code: 'cattle', group: 'livestock', en: 'Cattle', ar: 'أبقار', nl: 'Runderen', icon: Icons.pets_rounded, emoji: '🐄', diseaseScopeAliases: ['cattle', 'cow', 'calf', 'bovine']),
  VetAnimalSpecies(code: 'buffalo', group: 'livestock', en: 'Buffalo', ar: 'جاموس', nl: 'Buffels', icon: Icons.pets_rounded, emoji: '🐃', diseaseScopeAliases: ['buffalo', 'water buffalo']),
  VetAnimalSpecies(code: 'sheep', group: 'livestock', en: 'Sheep', ar: 'أغنام / خراف', nl: 'Schapen', icon: Icons.pets_rounded, emoji: '🐑', diseaseScopeAliases: ['sheep', 'lamb', 'ovine']),
  VetAnimalSpecies(code: 'goat', group: 'livestock', en: 'Goats', ar: 'ماعز', nl: 'Geiten', icon: Icons.pets_rounded, emoji: '🐐', diseaseScopeAliases: ['goat', 'kid', 'caprine']),
  VetAnimalSpecies(code: 'camel', group: 'livestock', en: 'Camels', ar: 'إبل / جمال', nl: 'Kamelen', icon: Icons.pets_rounded, emoji: '🐪', diseaseScopeAliases: ['camel', 'camelid']),
];

const vetBirdSpecies = <VetAnimalSpecies>[
  VetAnimalSpecies(code: 'chicken', group: 'poultry', en: 'Chickens', ar: 'دجاج', nl: 'Kippen', icon: Icons.flutter_dash_rounded, emoji: '🐔', diseaseScopeAliases: ['chicken', 'poultry', 'hen', 'rooster']),
  VetAnimalSpecies(code: 'chick', group: 'poultry', en: 'Chicks', ar: 'كتاكيت', nl: 'Kuikens', icon: Icons.flutter_dash_rounded, emoji: '🐣', diseaseScopeAliases: ['chick', 'chicken', 'poultry']),
  VetAnimalSpecies(code: 'duck', group: 'poultry', en: 'Ducks', ar: 'بط', nl: 'Eenden', icon: Icons.flutter_dash_rounded, emoji: '🦆', diseaseScopeAliases: ['duck', 'waterfowl']),
  VetAnimalSpecies(code: 'turkey', group: 'poultry', en: 'Turkeys', ar: 'ديك رومي', nl: 'Kalkoenen', icon: Icons.flutter_dash_rounded, emoji: '🦃', diseaseScopeAliases: ['turkey', 'poultry']),
  VetAnimalSpecies(code: 'goose', group: 'poultry', en: 'Geese', ar: 'أوز', nl: 'Ganzen', icon: Icons.flutter_dash_rounded, emoji: '🪿', diseaseScopeAliases: ['goose', 'geese', 'waterfowl']),
  VetAnimalSpecies(code: 'quail', group: 'poultry', en: 'Quail', ar: 'سمان', nl: 'Kwartels', icon: Icons.flutter_dash_rounded, emoji: '🐦', diseaseScopeAliases: ['quail', 'poultry']),
];

const vetDogSpecies = VetAnimalSpecies(
  code: 'dog',
  group: 'dogs',
  en: 'Dogs',
  ar: 'كلاب',
  nl: 'Honden',
  icon: Icons.pets_rounded,
  emoji: '🐕',
  diseaseScopeAliases: ['dog', 'canine'],
);

const vetDogBreeds = <VetDogBreed>[
  VetDogBreed(code: 'german_shepherd', en: 'German Shepherd', ar: 'جيرمن شيبرد', nl: 'Duitse herder'),
  VetDogBreed(code: 'belgian_malinois', en: 'Belgian Malinois', ar: 'مالينوي بلجيكي', nl: 'Mechelse herder'),
  VetDogBreed(code: 'rottweiler', en: 'Rottweiler', ar: 'روت وايلر', nl: 'Rottweiler'),
  VetDogBreed(code: 'labrador', en: 'Labrador Retriever', ar: 'لابرادور', nl: 'Labrador retriever'),
  VetDogBreed(code: 'golden_retriever', en: 'Golden Retriever', ar: 'جولدن ريتريفر', nl: 'Golden retriever'),
  VetDogBreed(code: 'doberman', en: 'Doberman', ar: 'دوبرمان', nl: 'Dobermann'),
  VetDogBreed(code: 'cane_corso', en: 'Cane Corso', ar: 'كاني كورسو', nl: 'Cane corso'),
  VetDogBreed(code: 'pitbull_amstaff', en: 'Pit Bull / AmStaff', ar: 'بيتبول / أمستاف', nl: 'Pitbull / AmStaff'),
  VetDogBreed(code: 'husky', en: 'Siberian Husky', ar: 'هاسكي', nl: 'Siberische husky'),
  VetDogBreed(code: 'border_collie', en: 'Border Collie', ar: 'بوردر كولي', nl: 'Border collie'),
  VetDogBreed(code: 'boxer', en: 'Boxer', ar: 'بوكسر', nl: 'Boxer'),
  VetDogBreed(code: 'great_dane', en: 'Great Dane', ar: 'جريت دان', nl: 'Duitse dog'),
  VetDogBreed(code: 'mastiff', en: 'Mastiff', ar: 'ماستيف', nl: 'Mastiff'),
  VetDogBreed(code: 'beagle', en: 'Beagle', ar: 'بيجل', nl: 'Beagle'),
  VetDogBreed(code: 'poodle', en: 'Poodle', ar: 'بودل', nl: 'Poedel'),
  VetDogBreed(code: 'cocker_spaniel', en: 'Cocker Spaniel', ar: 'كوكر سبانيل', nl: 'Cocker spaniel'),
  VetDogBreed(code: 'shih_tzu', en: 'Shih Tzu', ar: 'شيه تزو', nl: 'Shih tzu'),
  VetDogBreed(code: 'pomeranian', en: 'Pomeranian', ar: 'بوميرانيان', nl: 'Pomeriaan'),
  VetDogBreed(code: 'chihuahua', en: 'Chihuahua', ar: 'تشيواوا', nl: 'Chihuahua'),
  VetDogBreed(code: 'mixed_other', en: 'Mixed / Other', ar: 'هجين / أخرى', nl: 'Kruising / anders'),
];

List<VetAnimalSpecies> vetSpeciesForGroup(String group) => switch (group) {
  'livestock' => vetLivestockSpecies,
  'poultry' => vetBirdSpecies,
  'dogs' => const [vetDogSpecies],
  _ => const <VetAnimalSpecies>[],
};

VetAnimalSpecies? vetSpeciesByCode(String code) {
  final normalized = code.trim().toLowerCase();
  for (final s in [...vetLivestockSpecies, ...vetBirdSpecies, vetDogSpecies]) {
    if (s.code == normalized) return s;
  }
  return null;
}
