import 'package:flutter/material.dart';

class VetAnimalSpecies {
  const VetAnimalSpecies({
    required this.code,
    required this.group,
    required this.en,
    required this.ar,
    required this.nl,
    required this.icon,
    this.diseaseScopeAliases = const [],
  });

  final String code;
  final String group;
  final String en;
  final String ar;
  final String nl;
  final IconData icon;
  final List<String> diseaseScopeAliases;
}

const vetLivestockSpecies = <VetAnimalSpecies>[
  VetAnimalSpecies(code: 'cattle', group: 'livestock', en: 'Cattle', ar: 'أبقار', nl: 'Runderen', icon: Icons.agriculture_rounded, diseaseScopeAliases: ['cattle', 'cow', 'calf', 'bovine']),
  VetAnimalSpecies(code: 'buffalo', group: 'livestock', en: 'Buffalo', ar: 'جاموس', nl: 'Buffels', icon: Icons.agriculture_rounded, diseaseScopeAliases: ['buffalo', 'water buffalo']),
  VetAnimalSpecies(code: 'sheep', group: 'livestock', en: 'Sheep', ar: 'أغنام / خراف', nl: 'Schapen', icon: Icons.agriculture_rounded, diseaseScopeAliases: ['sheep', 'lamb', 'ovine']),
  VetAnimalSpecies(code: 'goat', group: 'livestock', en: 'Goats', ar: 'ماعز', nl: 'Geiten', icon: Icons.agriculture_rounded, diseaseScopeAliases: ['goat', 'kid', 'caprine']),
  VetAnimalSpecies(code: 'camel', group: 'livestock', en: 'Camels', ar: 'إبل / جمال', nl: 'Kamelen', icon: Icons.agriculture_rounded, diseaseScopeAliases: ['camel', 'camelid']),
];

const vetBirdSpecies = <VetAnimalSpecies>[
  VetAnimalSpecies(code: 'chicken', group: 'poultry', en: 'Chickens', ar: 'دجاج', nl: 'Kippen', icon: Icons.flutter_dash_rounded, diseaseScopeAliases: ['chicken', 'poultry', 'hen', 'rooster']),
  VetAnimalSpecies(code: 'chick', group: 'poultry', en: 'Chicks', ar: 'كتاكيت', nl: 'Kuikens', icon: Icons.flutter_dash_rounded, diseaseScopeAliases: ['chick', 'chicken', 'poultry']),
  VetAnimalSpecies(code: 'duck', group: 'poultry', en: 'Ducks', ar: 'بط', nl: 'Eenden', icon: Icons.flutter_dash_rounded, diseaseScopeAliases: ['duck', 'waterfowl']),
  VetAnimalSpecies(code: 'turkey', group: 'poultry', en: 'Turkeys', ar: 'ديك رومي', nl: 'Kalkoenen', icon: Icons.flutter_dash_rounded, diseaseScopeAliases: ['turkey', 'poultry']),
  VetAnimalSpecies(code: 'goose', group: 'poultry', en: 'Geese', ar: 'أوز', nl: 'Ganzen', icon: Icons.flutter_dash_rounded, diseaseScopeAliases: ['goose', 'geese', 'waterfowl']),
  VetAnimalSpecies(code: 'quail', group: 'poultry', en: 'Quail', ar: 'سمان', nl: 'Kwartels', icon: Icons.flutter_dash_rounded, diseaseScopeAliases: ['quail', 'poultry']),
];

const vetDogSpecies = VetAnimalSpecies(
  code: 'dog',
  group: 'dogs',
  en: 'Dogs',
  ar: 'كلاب',
  nl: 'Honden',
  icon: Icons.pets_rounded,
  diseaseScopeAliases: ['dog', 'canine'],
);

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
