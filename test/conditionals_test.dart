// Copyright (C) 2021-2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// conditionals_test.dart
// Unit tests for conditional calculations (e.g. always_comb, always_ff)
//
// 2021 May 7
// Author: Max Korbel <max.korbel@intel.com>

import 'dart:async';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class ShorthandAssignModule extends Module {
  final bool useArrays;

  @override
  Logic addInput(String name, Logic x, {int width = 1}) {
    assert(width.isEven, 'if arrays, split width in 2');
    if (useArrays) {
      return super
          .addInputArray(name, x, dimensions: [2], elementWidth: width ~/ 2);
    } else {
      return super.addInput(name, x, width: width);
    }
  }

  @override
  Logic addOutput(String name, {int width = 1}) {
    assert(width.isEven, 'if arrays, split width in 2');
    if (useArrays) {
      return super
          .addOutputArray(name, dimensions: [2], elementWidth: width ~/ 2);
    } else {
      return super.addOutput(name, width: width);
    }
  }

  ShorthandAssignModule(
      Logic preIncr, Logic preDecr, Logic mulAssign, Logic divAssign, Logic b,
      {this.useArrays = false})
      : super(name: 'shorthandmodule') {
    preIncr = addInput('preIncr', preIncr, width: 8);
    preDecr = addInput('preDecr', preDecr, width: 8);
    mulAssign = addInput('mulAssign', mulAssign, width: 8);
    divAssign = addInput('divAssign', divAssign, width: 8);
    b = addInput('b', b, width: 8);

    final piOut = addOutput('piOut', width: 8);
    final pdOut = addOutput('pdOut', width: 8);
    final maOut = addOutput('maOut', width: 8);
    final daOut = addOutput('daOut', width: 8);
    final piOutWithB = addOutput('piOutWithB', width: 8);
    final pdOutWithB = addOutput('pdOutWithB', width: 8);

    Combinational.ssa((s) => [
          s(piOutWithB) < preIncr,
          s(pdOutWithB) < preDecr,
          s(piOut) < preIncr,
          s(pdOut) < preDecr,
          s(maOut) < mulAssign,
          s(daOut) < divAssign,
          // Add these tests
          piOut.incr(s: s),
          pdOut.decr(s: s),
          piOutWithB.incr(s: s, val: b),
          pdOutWithB.decr(s: s, val: b),
          maOut.mulAssign(b, s: s),
          daOut.divAssign(b, s: s),
        ]);
  }
}

class LoopyCombModule extends Module {
  Logic get a => input('a');
  Logic get x => output('x');
  LoopyCombModule(Logic a) : super(name: 'loopycombmodule') {
    a = addInput('a', a);
    final x = addOutput('x');

    Combinational([
      x < a,
      x < ~x,
    ]);
  }
}

class LoopyCombModuleSsa extends Module {
  Logic get a => input('a');
  Logic get x => output('x');
  LoopyCombModuleSsa(Logic a) : super(name: 'loopycombmodule') {
    a = addInput('a', a);
    final x = addOutput('x');

    Combinational.ssa((s) => [
          s(x) < a,
          s(x) < ~s(x),
        ]);
  }
}

class CaseModule extends Module {
  CaseModule(Logic a, Logic b) : super(name: 'casemodule') {
    a = addInput('a', a);
    b = addInput('b', b);
    final c = addOutput('c');
    final d = addOutput('d');
    final e = addOutput('e');

    Combinational([
      Case(
          [b, a].swizzle(),
          [
            CaseItem(Const(LogicValue.ofString('01')), [c < 1, d < 0]),
            CaseItem(Const(LogicValue.ofString('10')), [
              c < 1,
              d < 0,
            ]),
          ],
          defaultItem: [
            c < 0,
            d < 1,
          ],
          conditionalType: ConditionalType.unique),
      CaseZ(
          [b, a].rswizzle(),
          [
            CaseItem(Const(LogicValue.ofString('1z')), [
              e < 1,
            ])
          ],
          defaultItem: [
            e < 0,
          ],
          conditionalType: ConditionalType.priority)
    ]);
  }
}

class UniqueCase extends Module {
  UniqueCase(Logic a, Logic b) : super(name: 'UniqueCase') {
    a = addInput('a', a);
    b = addInput('b', b);
    final c = addOutput('c');
    final d = addOutput('d');
    Combinational([
      Case(
          Const(1),
          [
            CaseItem(a, [c < 1, d < 0]),
            CaseItem(b, [c < 1, d < 0]),
          ],
          defaultItem: [
            c < 0,
            d < 1,
          ],
          conditionalType: ConditionalType.unique),
    ]);
  }
}

enum SeqCondModuleType { caseNormal, caseZ, ifNormal }

class ConditionalAssignModule extends Module {
  ConditionalAssignModule(
    Logic a,
  ) : super(name: 'ConditionalAssignModule') {
    a = addInput('a', a);
    final c = addOutput('c');
    Combinational([c < a]);
  }
}

class SeqCondModule extends Module {
  Logic get equal => output('equal');
  SeqCondModule(Logic clk, Logic a, {required SeqCondModuleType combType}) {
    a = addInput('a', a, width: 8);
    clk = addInput('clk', clk);

    addOutput('equal');

    final aIncr = a + 1;

    final aIncrDelayed = FlipFlop(clk, aIncr).q;

    final genCase =
        combType == SeqCondModuleType.caseNormal ? Case.new : CaseZ.new;

    Sequential(clk, [
      if (combType == SeqCondModuleType.ifNormal)
        If(
          aIncr.eq(aIncrDelayed),
          then: [equal < 1],
          orElse: [equal < 0],
        )
      else
        genCase(aIncr, [
          CaseItem(aIncrDelayed, [
            equal < 1,
          ])
        ], defaultItem: [
          equal < 0,
        ]),
    ]);
  }
}

class IfBlockModule extends Module {
  IfBlockModule(Logic a, Logic b) : super(name: 'ifblockmodule') {
    a = addInput('a', a);
    b = addInput('b', b);
    final c = addOutput('c');
    final d = addOutput('d');

    Combinational([
      If.block([
        Iff(a & ~b, [c < 1, d < 0]),
        ElseIf(b & ~a, [c < 1, d < 0]),
        Else([c < 0, d < 1])
      ])
    ]);
  }
}

class IffModule extends Module {
  IffModule(Logic a, Logic b) : super(name: 'Iffmodule') {
    a = addInput('a', a);
    b = addInput('b', b);
    final c = addOutput('c');

    Combinational([
      If(a, then: [c < b])
    ]);
  }
}

class SingleIfBlockModule extends Module {
  SingleIfBlockModule(Logic a) : super(name: 'singleifblockmodule') {
    a = addInput('a', a);
    final c = addOutput('c');

    Combinational([
      If.block([
        Iff.s(a, c < 1),
      ])
    ]);
  }
}

class ElseIfBlockModule extends Module {
  ElseIfBlockModule(Logic a, Logic b) : super(name: 'ifblockmodule') {
    a = addInput('a', a);
    b = addInput('b', b);
    final c = addOutput('c');
    final d = addOutput('d');

    Combinational([
      If.block([
        ElseIf(a & ~b, [c < 1, d < 0]),
        ElseIf(b & ~a, [c < 1, d < 0]),
        Else([c < 0, d < 1])
      ])
    ]);
  }
}

class SingleElseIfBlockModule extends Module {
  SingleElseIfBlockModule(Logic a) : super(name: 'singleifblockmodule') {
    a = addInput('a', a);
    final c = addOutput('c');
    final d = addOutput('d');

    Combinational([
      If.block([
        ElseIf.s(a, c < 1),
        Else([c < 0, d < 1])
      ])
    ]);
  }
}

class CombModule extends Module {
  CombModule(Logic a, Logic b, Logic d) : super(name: 'combmodule') {
    a = addInput('a', a);
    b = addInput('b', b);
    final y = addOutput('y');
    final z = addOutput('z');
    final x = addOutput('x');

    d = addInput('d', d, width: d.width);
    final q = addOutput('q', width: d.width);

    Combinational([
      If(a, then: [
        y < a,
        z < b,
        x < a & b,
        q < d,
      ], orElse: [
        If(b, then: [
          y < b,
          z < a,
          q < 13,
        ], orElse: [
          y < 0,
          z < 1,
        ])
      ])
    ]);
  }
}

class SequentialModule extends Module {
  SequentialModule(Logic a, Logic b, Logic d) : super(name: 'ffmodule') {
    a = addInput('a', a);
    b = addInput('b', b);
    final y = addOutput('y');
    final z = addOutput('z');
    final x = addOutput('x');

    d = addInput('d', d, width: d.width);
    final q = addOutput('q', width: d.width);

    Sequential(SimpleClockGenerator(10).clk, [
      If(a, then: [
        q < d,
        y < a,
        z < b,
        x < ~x, // invert x when a
      ], orElse: [
        x < a, // reset x to a when not a
        If(b, then: [
          y < b,
          z < a
        ], orElse: [
          y < 0,
          z < 1,
        ])
      ])
    ]);
  }
}

class SingleIfModule extends Module {
  SingleIfModule(Logic a) : super(name: 'combmodule') {
    a = addInput('a', a);

    final q = addOutput('q');

    Combinational(
      [
        If.s(a, q < 1),
      ],
    );
  }
}

class SingleIfOrElseModule extends Module {
  SingleIfOrElseModule(Logic a, Logic b) : super(name: 'combmodule') {
    a = addInput('a', a);
    b = addInput('b', b);

    final q = addOutput('q');
    final x = addOutput('x');

    Combinational(
      [
        If.s(a, q < 1, x < 1),
      ],
    );
  }
}

class SingleElseModule extends Module {
  SingleElseModule(Logic a, Logic b) : super(name: 'combmodule') {
    a = addInput('a', a);
    b = addInput('b', b);

    final q = addOutput('q');
    final x = addOutput('x');

    Combinational([
      If.block([
        Iff.s(a, q < 1),
        Else.s(x < 1),
      ])
    ]);
  }
}

class SignalRedrivenSequentialModule extends Module {
  SignalRedrivenSequentialModule(Logic a, Logic b, Logic d,
      {required bool allowRedrive})
      : super(name: 'ffmodule') {
    a = addInput('a', a);
    b = addInput('b', b);

    final q = addOutput('q', width: d.width);
    d = addInput('d', d, width: d.width);

    final k = addOutput('k', width: 8);
    Sequential(
      SimpleClockGenerator(10).clk,
      [
        If(a, then: [
          k < k,
          q < k,
          q < d,
        ])
      ],
      allowMultipleAssignments: allowRedrive,
    );
  }
}

class SignalRedrivenSequentialModuleWithX extends Module {
  SignalRedrivenSequentialModuleWithX(Logic a, Logic c, Logic d)
      : super(name: 'redrivenwithvalidinvalidsignal') {
    a = addInput('a', a);
    c = addInput('c', c);
    d = addInput('d', d);

    final b = addOutput('b');

    Sequential(
      SimpleClockGenerator(10).clk,
      [
        If(a, then: [b < c]),
        If(d, then: [b < c])
      ],
      allowMultipleAssignments: false,
    );
  }
}

class MultipleConditionalModule extends Module {
  MultipleConditionalModule(Logic a, Logic b)
      : super(name: 'multiplecondmodule') {
    a = addInput('a', a);
    b = addInput('b', b);
    final c = addOutput('c');

    final condOne = c < 1;

    Combinational([
      If.block([ElseIf.s(a, condOne), ElseIf.s(b, condOne)])
    ]);

    Combinational([
      If.block([ElseIf.s(a, condOne), ElseIf.s(b, condOne)])
    ]);
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('functional', () {
    group('conditional loopy comb', () {
      test('normal', () async {
        try {
          final mod = LoopyCombModule(Logic());
          await mod.build();
          mod.a.put(1);
          expect(mod.x.value.toInt(), equals(0));
          fail('Expected to throw an exception!');
        } on Exception catch (e) {
          expect(e.runtimeType, WriteAfterReadException);
        }
      });

      test('ssa', () async {
        final mod = LoopyCombModuleSsa(Logic());
        await mod.build();
        mod.a.put(1);
        expect(mod.x.value.toInt(), equals(0));
      });
    });

    group('flopped expressions for conditionals', () {
      for (final condType in SeqCondModuleType.values) {
        test(condType.name, () async {
          final clk = SimpleClockGenerator(10).clk;
          final a = Logic(name: 'a', width: 8);
          final mod = SeqCondModule(clk, a, combType: condType);

          a.put(0);

          Simulator.setMaxSimTime(100);

          unawaited(Simulator.run());

          await clk.nextPosedge;
          a.put(1);
          await clk.nextPosedge;
          a.put(2);
          await clk.nextPosedge;

          expect(mod.equal.value.toBool(), false);

          await Simulator.simulationEnded;
        });
      }
    });

    group('bad if blocks', () {
      test('IfBlock with only else fails', () async {
        expect(
            () => If.block([
                  Else([]),
                ]),
            throwsException);
      });

      test('IfBlock with else in the middle fails', () {
        expect(
            () => If.block([
                  ElseIf(Logic(), []),
                  Else([]),
                  ElseIf(Logic(), []),
                ]),
            throwsException);
      });

      test('IfBlock with else at the start fails', () {
        expect(
            () => If.block([
                  Else([]),
                  ElseIf(Logic(), []),
                ]),
            throwsException);
      });
    });
  });

  group('simcompare', () {
    test('conditional comb', () async {
      final mod = CombModule(Logic(), Logic(), Logic(width: 10));
      await mod.build();
      final vectors = [
        Vector({'a': 0, 'b': 0, 'd': 5},
            {'y': 0, 'z': 1, 'x': LogicValue.x, 'q': LogicValue.x}),
        Vector({'a': 0, 'b': 1, 'd': 6},
            {'y': 1, 'z': 0, 'x': LogicValue.x, 'q': 13}),
        Vector({'a': 1, 'b': 0, 'd': 7}, {'y': 1, 'z': 0, 'x': 0, 'q': 7}),
        Vector({'a': 1, 'b': 1, 'd': 8}, {'y': 1, 'z': 1, 'x': 1, 'q': 8}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      final simResult = SimCompare.iverilogVector(mod, vectors);
      expect(simResult, equals(true));
    });

    test('iffblock comb', () async {
      final mod = IfBlockModule(Logic(), Logic());
      await mod.build();
      final vectors = [
        Vector({'a': 0, 'b': 0}, {'c': 0, 'd': 1}),
        Vector({'a': 0, 'b': 1}, {'c': 1, 'd': 0}),
        Vector({'a': 1, 'b': 0}, {'c': 1, 'd': 0}),
        Vector({'a': 1, 'b': 1}, {'c': 0, 'd': 1}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      final simResult = SimCompare.iverilogVector(mod, vectors);
      expect(simResult, equals(true));
    });

    test('if invalid ', () async {
      final mod = IffModule(Logic(), Logic());
      await mod.build();
      final vectors = [
        Vector({'a': 1, 'b': 0}, {'c': 0}),
        Vector({'a': LogicValue.z, 'b': 1}, {'c': LogicValue.x}),
        Vector({'a': LogicValue.x, 'b': 0}, {'c': LogicValue.x}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
    });

    test('single iffblock comb', () async {
      final mod = SingleIfBlockModule(Logic());
      await mod.build();
      final vectors = [
        Vector({'a': 1}, {'c': 1}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      final simResult = SimCompare.iverilogVector(mod, vectors);
      expect(simResult, equals(true));
    });

    test('elseifblock comb', () async {
      final mod = ElseIfBlockModule(Logic(), Logic());
      await mod.build();
      final vectors = [
        Vector({'a': 0, 'b': 0}, {'c': 0, 'd': 1}),
        Vector({'a': 0, 'b': 1}, {'c': 1, 'd': 0}),
        Vector({'a': 1, 'b': 0}, {'c': 1, 'd': 0}),
        Vector({'a': 1, 'b': 1}, {'c': 0, 'd': 1}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      final simResult = SimCompare.iverilogVector(mod, vectors);
      expect(simResult, equals(true));
    });

    test('Conditional assign module with invalid inputs', () async {
      final mod = ConditionalAssignModule(Logic());
      await mod.build();
      final vectors = [
        Vector({'a': 1}, {'c': 1}),
        Vector({'a': 0}, {'c': 0}),
        Vector({'a': LogicValue.z}, {'c': LogicValue.x}),
        Vector({'a': LogicValue.x}, {'c': LogicValue.x}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
    });

    test('single elseifblock comb', () async {
      final mod = SingleElseIfBlockModule(Logic());
      await mod.build();
      final vectors = [
        Vector({'a': 1}, {'c': 1}),
        Vector({'a': 0}, {'c': 0, 'd': 1}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      final simResult = SimCompare.iverilogVector(mod, vectors);
      expect(simResult, equals(true));
    });

    test('case comb', () async {
      final mod = CaseModule(Logic(), Logic());
      await mod.build();
      final vectors = [
        Vector({'a': 0, 'b': 0}, {'c': 0, 'd': 1, 'e': 0}),
        Vector({'a': 0, 'b': 1}, {'c': 1, 'd': 0, 'e': 0}),
        Vector({'a': 1, 'b': 0}, {'c': 1, 'd': 0, 'e': 1}),
        Vector({'a': 1, 'b': 1}, {'c': 0, 'd': 1, 'e': 1}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      final simResult = SimCompare.iverilogVector(mod, vectors);
      expect(simResult, equals(true));
    });

    test('Unique case', () async {
      final mod = UniqueCase(Logic(), Logic());
      await mod.build();
      final vectors = [
        Vector({'a': 0, 'b': 0}, {'c': 0, 'd': 1}),
        Vector({'a': 0, 'b': 1}, {'c': 1, 'd': 0}),
        Vector({'a': 1, 'b': 0}, {'c': 1, 'd': 0}),
        Vector({'a': 1, 'b': 1}, {'c': LogicValue.x, 'd': LogicValue.x}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
    });

    test('conditional ff', () async {
      final mod = SequentialModule(Logic(), Logic(), Logic(width: 8));
      await mod.build();
      final vectors = [
        Vector({'a': 1, 'd': 1}, {}),
        Vector({'a': 0, 'b': 0, 'd': 2}, {'q': 1}),
        Vector({'a': 0, 'b': 1, 'd': 3}, {'y': 0, 'z': 1, 'x': 0, 'q': 1}),
        Vector({'a': 1, 'b': 0, 'd': 4}, {'y': 1, 'z': 0, 'x': 0, 'q': 1}),
        Vector({'a': 1, 'b': 1, 'd': 5}, {'y': 1, 'z': 0, 'x': 1, 'q': 4}),
        Vector({}, {'y': 1, 'z': 1, 'x': 0, 'q': 5}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      final simResult = SimCompare.iverilogVector(mod, vectors);
      expect(simResult, equals(true));
    });

    test('should return exception if a conditional is used multiple times.',
        () async {
      expect(
          () => MultipleConditionalModule(Logic(), Logic()), throwsException);
    });
  });

  test(
      'should return true on simcompare when '
      'execute if.s() for single if...else conditional without orElse.',
      () async {
    final mod = SingleIfModule(Logic());
    await mod.build();
    final vectors = [
      Vector({'a': 1}, {'q': 1}),
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    final simResult = SimCompare.iverilogVector(mod, vectors);
    expect(simResult, equals(true));
  });

  test(
      'should return true on simcompare when '
      'execute if.s() for single if...else conditional with orElse.', () async {
    final mod = SingleIfOrElseModule(Logic(), Logic());
    await mod.build();
    final vectors = [
      Vector({'a': 1}, {'q': 1}),
      Vector({'a': 0}, {'x': 1}),
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    final simResult = SimCompare.iverilogVector(mod, vectors);
    expect(simResult, equals(true));
  });

  test(
      'should return true on simcompare when '
      'execute Else.s() for single else conditional', () async {
    final mod = SingleElseModule(Logic(), Logic());
    await mod.build();
    final vectors = [
      Vector({'a': 1}, {'q': 1}),
      Vector({'a': 0}, {'x': 1}),
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    final simResult = SimCompare.iverilogVector(mod, vectors);
    expect(simResult, equals(true));
  });

  test(
      'should return SignalRedrivenException when there are multiple drivers '
      'for a flop when redrive not allowed.', () async {
    final mod = SignalRedrivenSequentialModule(
        Logic(), Logic(), Logic(width: 8),
        allowRedrive: false);
    await mod.build();
    final vectors = [
      Vector({'a': 1, 'd': 1}, {}),
      Vector({'a': 0, 'b': 0, 'd': 2}, {'q': 1}),
    ];

    try {
      await SimCompare.checkFunctionalVector(mod, vectors);
      fail('Exception not thrown!');
    } on Exception catch (e) {
      expect(e.runtimeType, equals(SignalRedrivenException));
    }
  });

  test('should allow redrive when allowed', () async {
    final mod = SignalRedrivenSequentialModule(
        Logic(), Logic(), Logic(width: 8),
        allowRedrive: true);
    await mod.build();
    final vectors = [
      Vector({'a': 1, 'd': 1}, {}),
      Vector({'a': 1, 'b': 0, 'd': 2}, {'q': 1}),
      Vector({'a': 1, 'b': 0, 'd': 3}, {'q': 2}),
    ];

    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test(
      'should return NonSupportedTypeException when '
      'simcompare expected output values has invalid runtime type. ', () async {
    final mod = SequentialModule(Logic(), Logic(), Logic(width: 8));
    await mod.build();
    final vectors = [
      Vector({'a': 1, 'd': 1}, {}),
      Vector({'a': 0, 'b': 0, 'd': 2}, {'q': 'invalid runtime type'}),
    ];

    try {
      await SimCompare.checkFunctionalVector(mod, vectors);
      fail('Exception not thrown!');
    } on Exception catch (e) {
      expect(e.runtimeType, equals(NonSupportedTypeException));
    }
  });

  test(
      'should return SignalRedrivenException when driven with '
      'x signals and valid signals when redrive not allowed.', () async {
    final mod = SignalRedrivenSequentialModuleWithX(Logic(), Logic(), Logic());
    await mod.build();
    final vectors = [
      Vector({'a': LogicValue.x, 'd': 1, 'c': 1}, {'b': LogicValue.z}),
      Vector({'a': 1, 'd': 1, 'c': 1}, {'b': 1}),
    ];

    try {
      await SimCompare.checkFunctionalVector(mod, vectors);
      fail('Exception not thrown!');
    } on Exception catch (e) {
      expect(e.runtimeType, equals(SignalRedrivenException));
    }
  });

  group('shorthand operations', () {
    Future<void> testShorthand(
        {required bool useArrays, required bool useSequential}) async {
      final mod = ShorthandAssignModule(
        Logic(width: 8),
        Logic(width: 8),
        Logic(width: 8),
        Logic(width: 8),
        Logic(width: 8),
        useArrays: useArrays,
      );
      await mod.build();

      final vectors = [
        Vector({
          'preIncr': 5,
          'preDecr': 5,
          'mulAssign': 5,
          'divAssign': 5,
          'b': 5
        }, {
          'piOutWithB': 10,
          'pdOutWithB': 0,
          'piOut': 6,
          'pdOut': 4,
          'maOut': 25,
          'daOut': 1,
        }),
        Vector({
          'preIncr': 5,
          'preDecr': 5,
          'mulAssign': 5,
          'divAssign': 5,
          'b': 0
        }, {
          'piOutWithB': 5,
          'pdOutWithB': 5,
          'piOut': 6,
          'pdOut': 4,
          'maOut': 0,
          'daOut': LogicValue.x,
        }),
        Vector({
          'preIncr': 0,
          'preDecr': 0,
          'mulAssign': 0,
          'divAssign': 0,
          'b': 5
        }, {
          'piOutWithB': 5,
          'pdOutWithB': 0xfb,
          'piOut': 1,
          'pdOut': 0xff,
          'maOut': 0,
          'daOut': 0,
        })
      ];

      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    }

    test('normal logic', () async {
      await testShorthand(useArrays: false, useSequential: false);
    });

    test('arrays', () async {
      await testShorthand(useArrays: true, useSequential: false);
    });
  });
}
