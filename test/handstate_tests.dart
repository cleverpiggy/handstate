import 'package:test/test.dart';
import 'package:handstate/handstate.dart';

void main() {
  test('Action.fromString returns an action', testActionFromString);
  test('Action.amount', testActionAmount);
  test('Status.incr', testStatusIncr);
  test('Status.amount', testStatusAmount);
  test('Status ord', testStatusOrd);
  test('HandState().withHistory', testHandstateWithHistory);
  test('call and raise amounts', testCallAndRaiseAmounts);
  test('legal actions', testHandstateLegalActions);
  test('individual isLegal', testHandstateIsLegal);
  test('individual isLegal fails', testHandstateIsNotLegal);
  test('all ins', testAllins);
}

void testActionFromString() {
  expect(Action.fromString("C5"), equals(Action.call(5)));
  expect(Action.fromString("R10"), equals(Action.raise(10)));
  expect(Action.fromString("F"), equals(Action.fold()));
  expect(Action.fromString("P10"), equals(Action.post(10)));

  expect(Action.fromString("R"), equals(null));
  expect(Action.fromString("X"), equals(null));
}

void testActionAmount() {
  expect(Action.fold().amount, 0);
  expect(Action.call(10).amount, 10);
  expect(Action.raise(20).amount, 20);
  expect(Action.post(10).amount, 10);
  expect(Action.call(0).amount, 0);
}

void testStatusIncr() {
  expect(Status.hasntActed(10).incr(20), equals(Status.infor(30)));
  expect(Status.infor(0).incr(20), equals(Status.infor(20)));
  expect(() => Status.out().incr(20), throwsFormatException);
}

void testStatusAmount() {
  expect(Status.hasntActed(20).amount, 20);
  expect(Status.infor(30).amount, 30);
}

void testStatusOrd() {
  expect(Status.out(), lessThan(Status.hasntActed(10)));
  expect(Status.hasntActed(5), lessThan(Status.hasntActed(10)));
  expect(Status.hasntActed(10), equals(Status.hasntActed(10)));
  expect(Status.infor(5), equals(Status.infor(5)));
  expect(Status.infor(5), lessThan(Status.infor(15)));
}

HandState trialHandstate() {
  final button = 0;
  final sb = 10;
  final stacks = [for (var i = 0; i < 6; i++) 1000];
  return HandState(stacks: stacks, button: button, sb: sb);
}

void testHandstateWithHistory() {
  var h = trialHandstate().withHistory("P10 P20");

  expect(h.bettingRounds, [
    [Action.post(10, seat: 1), Action.post(20, seat: 2)]
  ]);

  h = trialHandstate().withHistory("P10 P20 F F F R50 C40 C30 C0 R60");

  expect(h.bettingRounds[0].length, 8);
  expect(h.bettingRounds[1].length, 2);
  expect(h.bettingRounds[1].last, Action.raise(60, seat: 2));

  h = trialHandstate().withHistory(
    "P10 P20 F F F R50 C40 C30 C0 R60 C60 R150 F",
  );
  expect(h.bettingRounds[1].length, 5);
  expect(h.bettingRounds[1].getRange(3, 5).toList(),
      [Action.raise(150, seat: 1), Action.fold(seat: 2)]);
}

void testCallAndRaiseAmounts() {
  // total additional money to put in the pot
  final histories = [
    ["", 20, 40],
    ["R50", 50, 80],
    ["R50 R120 F", 120, 190],
    ["R50 R120 F F", 110, 180], // reraise to sb
    ["C20 F F F", 10, 30], // limp to sb
    ["R50 R120 F F F", 100, 170], // reraise to bb
    ["C20 F F F F", 0, 20], // limp to bb
    ["C20 F F F R60", 50, 100], // sb raises limp, on bb
    ["R50 F F F R100", 90, 150], // sb reraises, on bb
    ["R50 R120 F F F R250", 220, 370], // bb 4 bets, on original raiser
    ["R50 R120 F F F R250 F", 150, 300], // bb 4 bets, on 3 better
  ];
  for (var item in histories) {
    final history = item[0] as String;
    final call = item[1] as int;
    final raise = item[2] as int;
    final h = trialHandstate().withHistory("P10 P20").withHistory(history);

    final testCall = h.amountToCall();
    final testRaise = testCall + h.currentRaiseDelta;
    expect(testCall, call);
    expect(testRaise, raise);
  }
}

void testHandstateLegalActions() {
  var h = trialHandstate();
  expect(h.legalActions(), [Action.post(10)]);

  h = trialHandstate().withHistory("P10");
  expect(h.legalActions(), [Action.post(20)]);

  h = trialHandstate().withHistory("P10 P20");
  expect(h.legalActions(), [Action.fold(), Action.call(20), Action.raise(40)]);

  h = trialHandstate().withHistory("P10 P20 C20");
  expect(h.legalActions(), [Action.fold(), Action.call(20), Action.raise(40)]);

  // sb faces a limp
  h = trialHandstate().withHistory("P10 P20 C20 F F F");
  expect(h.legalActions(), [Action.fold(), Action.call(10), Action.raise(30)]);

  // folded to sb
  h = trialHandstate().withHistory("P10 P20 F F F F");
  expect(h.legalActions(), [Action.fold(), Action.call(10), Action.raise(30)]);

  // sb faces 60 raise
  h = trialHandstate().withHistory("P10 P20 C20 F F R60");
  expect(h.legalActions(), [Action.fold(), Action.call(50), Action.raise(90)]);

  // bb faces a limp and sb limp
  h = trialHandstate().withHistory("P10 P20 C20 F F F C10");
  expect(h.legalActions(), [Action.call(0), Action.raise(20)]);

  // bb faces a limp and sb fold
  h = trialHandstate().withHistory("P10 P20 C20 F F F F");
  expect(h.legalActions(), [Action.call(0), Action.raise(20)]);

  // bb checks, new round
  h = trialHandstate().withHistory("P10 P20 C20 F F F F C0");
  expect(h.legalActions(), [Action.call(0), Action.raise(20)]);

  // bb raises option 50 more
  h = trialHandstate().withHistory("P10 P20 C20 F F F F R50");
  expect(h.legalActions(), [Action.fold(), Action.call(50), Action.raise(100)]);
}

void testHandstateIsLegal() {
  // Copying in the strings from above function.
  // We've tested that legalActions is correct for
  // these so we now use the results of legalActions
  // to test the individual action checker - is_legal.
  final histories = [
    "P10",
    "P10 P20",
    "P10 P20 C20",
    "P10 P20 C20 F F F",
    "P10 P20 C20 F F R60",
    "P10 P20 C20 F F F C10",
    "P10 P20 C20 F F F F",
    "P10 P20 C20 F F F F C0",
    "P10 P20 C20 F F F F R50",
  ];

  final testPositive = (String h) {
    final hand = trialHandstate().withHistory(h);
    final isCorrect = hand.legalActions().every((a) => hand.isLegal(a));
    if (!isCorrect) {
      print("$h failed");
      for (var action in hand.legalActions()) {
        if (!hand.isLegal(action)) {
          print('action was considered illegal: $action');
        }
      }
    }
    return isCorrect;
  };

  expect(histories.every(testPositive), true);
}

void testHandstateIsNotLegal() {
  final histories = [
    "P15",
    "P10 P30",
    "P10 P20 C10",
    "P10 P20 C20 F F R30",
    "P10 P20 C20 F F C10",
    "P10 P20 C20 F F F C30",
    "P10 P20 C20 F F F F F",
    "P10 P20 C20 F F F F R10",
    "P10 P20 C20 F F F F R50 C20",
    "P10 P20 C20 F F F F R50 R30",
    "P10 P20 C20 F F F F R50 C70",
  ];

  final testPositive = (String h) {
    try {
      final hand = trialHandstate().withHistory(h);
      print('This should have thrown an exception:\n$hand');
      return false;
    } on FormatException {
      return true;
    }
  };
  expect(histories.every(testPositive), true);
}

void testAllins() {
  final button = 0;
  final h = HandState(stacks: [1000, 1000, 20], button: button, sb: 10)
      .withHistory("P10 P20");
  h.performAction(Action.raise(40));
  expect(h.isRoundFinished(), false);
  h.performAction(Action.call(30));
  expect(h.isRoundFinished(), true);
  h.startNewRound();
  // round Flop
  // sb bets 40
  // bb is allin
  h.performAction(Action.raise(40));
  expect(h.whosNext(), button);
  h.performAction(Action.call(40));
  expect(h.isRoundFinished(), true);

  expect(h.pot, 180);
  expect(h.stacks, [920, 920, 0]);
}
