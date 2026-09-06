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
    required this.spriteIndex,
    this.diseaseScopeAliases = const [],
  });

  final String code;
  final String group;
  final String en;
  final String ar;
  final String nl;
  final IconData icon;
  final String emoji;
  final int spriteIndex;
  final List<String> diseaseScopeAliases;
}

class VetDogBreed {
  const VetDogBreed({
    required this.code,
    required this.en,
    required this.ar,
    required this.nl,
    required this.spriteIndex,
  });
  final String code;
  final String en;
  final String ar;
  final String nl;
  final int spriteIndex;
}

const vetLivestockSpecies = <VetAnimalSpecies>[
  VetAnimalSpecies(
    code: 'cattle',
    group: 'livestock',
    en: 'Cattle',
    ar: 'أبقار',
    nl: 'Runderen',
    icon: Icons.pets_rounded,
    emoji: '🐄',
    spriteIndex: 3,
    diseaseScopeAliases: ['cattle', 'cow', 'calf', 'bovine'],
  ),
  VetAnimalSpecies(
    code: 'buffalo',
    group: 'livestock',
    en: 'Buffalo',
    ar: 'جاموس',
    nl: 'Buffels',
    icon: Icons.pets_rounded,
    emoji: '🐃',
    spriteIndex: 4,
    diseaseScopeAliases: ['buffalo', 'water buffalo'],
  ),
  VetAnimalSpecies(
    code: 'sheep',
    group: 'livestock',
    en: 'Sheep',
    ar: 'أغنام / خراف',
    nl: 'Schapen',
    icon: Icons.pets_rounded,
    emoji: '🐑',
    spriteIndex: 5,
    diseaseScopeAliases: ['sheep', 'lamb', 'ovine'],
  ),
  VetAnimalSpecies(
    code: 'goat',
    group: 'livestock',
    en: 'Goats',
    ar: 'ماعز',
    nl: 'Geiten',
    icon: Icons.pets_rounded,
    emoji: '🐐',
    spriteIndex: 6,
    diseaseScopeAliases: ['goat', 'kid', 'caprine'],
  ),
  VetAnimalSpecies(
    code: 'horse',
    group: 'livestock',
    en: 'Horses',
    ar: 'خيول / أحصنة',
    nl: 'Paarden',
    icon: Icons.pets_rounded,
    emoji: '🐎',
    spriteIndex: 7,
    diseaseScopeAliases: ['horse', 'equine', 'foal'],
  ),
];

const vetBirdSpecies = <VetAnimalSpecies>[
  VetAnimalSpecies(
    code: 'chicken',
    group: 'poultry',
    en: 'Chickens',
    ar: 'دجاج',
    nl: 'Kippen',
    icon: Icons.flutter_dash_rounded,
    emoji: '🐔',
    spriteIndex: 8,
    diseaseScopeAliases: ['chicken', 'poultry', 'hen', 'rooster'],
  ),
  VetAnimalSpecies(
    code: 'chick',
    group: 'poultry',
    en: 'Chicks',
    ar: 'كتاكيت',
    nl: 'Kuikens',
    icon: Icons.flutter_dash_rounded,
    emoji: '🐣',
    spriteIndex: 9,
    diseaseScopeAliases: ['chick', 'chicken', 'poultry'],
  ),
  VetAnimalSpecies(
    code: 'duck',
    group: 'poultry',
    en: 'Ducks',
    ar: 'بط',
    nl: 'Eenden',
    icon: Icons.flutter_dash_rounded,
    emoji: '🦆',
    spriteIndex: 10,
    diseaseScopeAliases: ['duck', 'waterfowl'],
  ),
  VetAnimalSpecies(
    code: 'turkey',
    group: 'poultry',
    en: 'Turkeys',
    ar: 'ديك رومي',
    nl: 'Kalkoenen',
    icon: Icons.flutter_dash_rounded,
    emoji: '🦃',
    spriteIndex: 11,
    diseaseScopeAliases: ['turkey', 'poultry'],
  ),
  VetAnimalSpecies(
    code: 'goose',
    group: 'poultry',
    en: 'Geese',
    ar: 'أوز',
    nl: 'Ganzen',
    icon: Icons.flutter_dash_rounded,
    emoji: '🪿',
    spriteIndex: 12,
    diseaseScopeAliases: ['goose', 'geese', 'waterfowl'],
  ),
];

const vetDogSpecies = VetAnimalSpecies(
  code: 'dog',
  group: 'dogs',
  en: 'Dogs',
  ar: 'كلاب',
  nl: 'Honden',
  icon: Icons.pets_rounded,
  emoji: '🐕',
  spriteIndex: 1,
  diseaseScopeAliases: ['dog', 'canine'],
);

const vetDogBreeds = <VetDogBreed>[
  VetDogBreed(
    code: 'german_shepherd',
    en: 'German Shepherd',
    ar: 'جيرمن شيبرد',
    nl: 'Duitse herder',
    spriteIndex: 13,
  ),
  VetDogBreed(
    code: 'belgian_malinois',
    en: 'Belgian Malinois',
    ar: 'مالينوي بلجيكي',
    nl: 'Mechelse herder',
    spriteIndex: 14,
  ),
  VetDogBreed(
    code: 'rottweiler',
    en: 'Rottweiler',
    ar: 'روت وايلر',
    nl: 'Rottweiler',
    spriteIndex: 15,
  ),
  VetDogBreed(
    code: 'labrador',
    en: 'Labrador Retriever',
    ar: 'لابرادور',
    nl: 'Labrador retriever',
    spriteIndex: 16,
  ),
  VetDogBreed(
    code: 'golden_retriever',
    en: 'Golden Retriever',
    ar: 'جولدن ريتريفر',
    nl: 'Golden retriever',
    spriteIndex: 17,
  ),
  VetDogBreed(
    code: 'doberman',
    en: 'Doberman',
    ar: 'دوبرمان',
    nl: 'Dobermann',
    spriteIndex: 18,
  ),
  VetDogBreed(
    code: 'cane_corso',
    en: 'Cane Corso',
    ar: 'كاني كورسو',
    nl: 'Cane corso',
    spriteIndex: 19,
  ),
  VetDogBreed(
    code: 'pitbull_amstaff',
    en: 'Pit Bull / AmStaff',
    ar: 'بيتبول / أمستاف',
    nl: 'Pitbull / AmStaff',
    spriteIndex: 20,
  ),
  VetDogBreed(
    code: 'husky',
    en: 'Siberian Husky',
    ar: 'هاسكي',
    nl: 'Siberische husky',
    spriteIndex: 21,
  ),
  VetDogBreed(
    code: 'chihuahua',
    en: 'Chihuahua',
    ar: 'تشيواوا',
    nl: 'Chihuahua',
    spriteIndex: 22,
  ),
  VetDogBreed(
    code: 'mixed_other',
    en: 'Mixed / Other',
    ar: 'هجين / أخرى',
    nl: 'Kruising / anders',
    spriteIndex: 1,
  ),
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
