import 'package:yaml/yaml.dart';

enum Priority { must, should, could }

enum Status { met, partial, notMet, na }

enum Severity { p0, p1, p2, p3 }

class Criterion {
  Criterion({
    required this.id,
    required this.priority,
    required this.status,
    this.automatedInCi = false,
    this.evidence,
    this.findings = const [],
    this.note,
  });

  final String id;
  final Priority priority;

  /// `null` means the criterion has not been assessed yet.
  final Status? status;
  final bool automatedInCi;
  final String? evidence;
  final List<String> findings;
  final String? note;
}

class Dimension {
  Dimension({
    required this.id,
    required this.weight,
    required this.gateMinMaturity,
    required this.criteria,
  });

  final String id;
  final int weight;

  /// `null` means the dimension is not gate-relevant.
  final int? gateMinMaturity;
  final List<Criterion> criteria;
}

class Finding {
  Finding({
    required this.id,
    required this.severity,
    required this.criterion,
    required this.freezeRelevant,
    required this.open,
  });

  final String id;
  final Severity severity;
  final String criterion;
  final bool freezeRelevant;
  final bool open;
}

class Catalog {
  Catalog({
    required this.meta,
    required this.dimensions,
    required this.findings,
  });

  final Map<String, Object?> meta;
  final List<Dimension> dimensions;
  final List<Finding> findings;
}

const _priorities = {'M': Priority.must, 'S': Priority.should, 'C': Priority.could};
const _statuses = {
  'met': Status.met,
  'partial': Status.partial,
  'not_met': Status.notMet,
  'na': Status.na,
};
const _severities = {
  'P0': Severity.p0,
  'P1': Severity.p1,
  'P2': Severity.p2,
  'P3': Severity.p3,
};

/// Parses `docs/audit/criteria.yaml`.
///
/// Throws [FormatException] on unknown enum values or missing required fields.
Catalog parseCatalog(String yamlSource) {
  final root = loadYaml(yamlSource);
  if (root is! YamlMap) throw const FormatException('root must be a map');
  final meta = <String, Object?>{
    for (final e in (root['meta'] as YamlMap? ?? YamlMap()).entries)
      '${e.key}': e.value,
  };
  final dimensions = [
    for (final d in _list(root, 'dimensions'))
      Dimension(
        id: _req<String>(d, 'id'),
        weight: _req<int>(d, 'weight'),
        gateMinMaturity: d['gate_min_maturity'] as int?,
        criteria: [
          for (final c in _list(d, 'criteria'))
            Criterion(
              id: _req<String>(c, 'id'),
              priority: _enum(_priorities, c['priority'], 'priority'),
              status: c['status'] == null
                  ? null
                  : _enum(_statuses, c['status'], 'status'),
              automatedInCi: c['automated_in_ci'] as bool? ?? false,
              evidence: c['evidence'] as String?,
              findings: [
                for (final f in (c['findings'] as YamlList? ?? YamlList())) '$f',
              ],
              note: c['note'] as String?,
            ),
        ],
      ),
  ];
  final findings = [
    for (final f in (root['findings'] as YamlList? ?? YamlList()))
      Finding(
        id: _req<String>(f as YamlMap, 'id'),
        severity: _enum(_severities, f['severity'], 'severity'),
        criterion: _req<String>(f, 'criterion'),
        freezeRelevant: f['freeze_relevant'] as bool? ?? false,
        open: switch (f['status']) {
          'open' => true,
          'closed' => false,
          final other => throw FormatException('unknown finding status: $other'),
        },
      ),
  ];
  return Catalog(meta: meta, dimensions: dimensions, findings: findings);
}

List<YamlMap> _list(YamlMap map, String key) {
  final value = map[key];
  if (value is! YamlList) throw FormatException('missing list: $key');
  return value.cast<YamlMap>();
}

T _req<T>(YamlMap map, String key) {
  final value = map[key];
  if (value is! T) throw FormatException('missing or invalid field: $key');
  return value;
}

E _enum<E>(Map<String, E> values, Object? raw, String field) {
  final value = values['$raw'];
  if (value == null) throw FormatException('unknown $field: $raw');
  return value;
}
