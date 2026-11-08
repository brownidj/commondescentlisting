/// Filing form only: preserve source names and exact transcript evidence.
String indexHeading(String value, {String category = ''}) {
  var heading = value.trim();
  heading = heading
      .replaceFirst(RegExp(r',\s*the$', caseSensitive: false), '')
      .trim();
  heading = heading
      .replaceFirst(RegExp(r'^the\s+', caseSensitive: false), '')
      .trim();
  if (category != 'fossil' && category != 'place') return heading;

  // Geological phases are filed under the named interval, not under Early/Late.
  // Do not mistake proper place names such as Middle East for geological phases.
  final phase = RegExp(
    r'^(early|earliest|middle|late|latest|lower|upper)\s+'
    r'(Precambrian|Hadean|Archean|Archaean|Proterozoic|Phanerozoic|'
    r'Paleozoic|Palaeozoic|Mesozoic|Cenozoic|Cainozoic|Cambrian|'
    r'Ordovician|Silurian|Devonian|Carboniferous|Mississippian|Pennsylvanian|'
    r'Permian|Triassic|Jurassic|Cretaceous|Cretatous|Paleogene|Palaeogene|'
    r'Neogene|Quaternary|Paleocene|Palaeocene|Eocene|Oligocene|Miocene|'
    r'Pliocene|Pleistocene|Holocene|Ediacaran|Cryogenian|Tonian)$',
    caseSensitive: false,
  ).firstMatch(heading);
  if (phase != null) {
    return '${phase.group(2)}, ${phase.group(1)!.toLowerCase()}';
  }
  if (heading.contains(',')) return heading;
  final words = heading.split(RegExp(r'\s+'));
  if (words.length < 2) return heading;
  const descriptors = {
    'herbivore',
    'herbivorous',
    'carnivore',
    'carnivorous',
    'omnivorous',
    'predatory',
    'marine',
    'aquatic',
    'freshwater',
    'terrestrial',
    'land',
    'land-dwelling',
    'ocean',
    'grass-eating',
    'plant-eating',
    'meat-eating',
    'ancient',
    'modern',
    'modern-day',
    'extinct',
    'living',
    'fossil',
    'early',
    'late',
    'small',
    'large',
    'giant',
    'tiny',
    'bony',
    'shelled',
    'soft-bodied',
    'hard-bodied',
    'vertebrate',
    'invertebrate',
    'toothy',
  };
  const heads = {
    'animal',
    'animals',
    'mammal',
    'mammals',
    'reptile',
    'reptiles',
    'amphibian',
    'amphibians',
    'bird',
    'birds',
    'fish',
    'fishes',
    'shark',
    'sharks',
    'crocodile',
    'crocodiles',
    'alligator',
    'alligators',
    'dinosaur',
    'dinosaurs',
    'whale',
    'whales',
    'marsupial',
    'marsupials',
    'kangaroo',
    'kangaroos',
    'arthropod',
    'arthropods',
    'spider',
    'spiders',
    'plant',
    'plants',
    'tree',
    'trees',
    'forest',
    'forests',
    'fossil',
    'fossils',
    'species',
    'genus',
    'genera',
    'organism',
    'organisms',
    'predator',
    'predators',
    'herbivore',
    'herbivores',
    'carnivore',
    'carnivores',
    'group',
    'groups',
    'community',
    'communities',
    'ecosystem',
    'ecosystems',
    'continent',
    'continents',
    'supercontinent',
    'supercontinents',
    'tetrapod',
    'tetrapods',
    'chordate',
    'chordates',
    'mollusk',
    'mollusks',
    'mollusc',
    'molluscs',
  };
  if (descriptors.contains(words.first.toLowerCase()) &&
      heads.contains(words.last.toLowerCase())) {
    final description = [
      words.first.toLowerCase(),
      ...words.skip(1).take(words.length - 2),
    ].join(' ');
    return '${words.last}, $description';
  }
  return heading;
}

String indexBlacklistKey(String value) =>
    indexHeading(value)
        .toLowerCase()
        .replaceAll(RegExp('[–—‑]'), '-')
        .replaceAll('’', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
