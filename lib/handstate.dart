//! This module defines the HandState struct to track a multiplayer
//! holdem hand.
//!
//! You can initialize a hand with 3 or more players of various
//! stack sizes and for various stakes.  A hand can be initialized
//! at the beginning or at any stage using an actions string.
//!
//! The HandState is queryeable in various ways to see what
//! has happened, whos turn it is, and what actions are legal.
//!
//! An import distinction has to be made as to what a "raise" or
//! call actually refers to.  Here, the value of either of those
//! actions declare how much additional money the player will put
//! into the pot, above what they have already bet.  Also, the
//! concepts of "bet" and "check" are not used as they are indistinguishable
//! from "raise" of a 0 bet and "call 0".

//! ie. starting from the first player on the flop:
//! - A:  Raise(20) ->  A has 20 in the pot
//! - B:  Raise(50) -> B has 50 in the pot (called 20 and raised 30)
//! - A:  Raise(100) -> A has 120 in the pot (called 30 and raised 70 more)
//! - B:  Call(70) -> B has 120 in the pot

// @TODO:  we are completely ignoring stacks when deciding if bets are legal

void main(List<String> args) {
  final handstring = args.join(' ');
  final h = HandState(
      button: 0, sb: 10, stacks: [1000, 1000, 1000, 1000, 1000, 1000]);
  print(h.withHistory(handstring));
  print(h.isLegal(Action.call(0)));
}

const int RIVER = 3;

class HandState {
  int sb;
  int button;
  int pot;
  List<String> board;
  List<List<Action>> bettingRounds;
  List<Status> infors;
  List<int> stacks;
  int currentRaiseDelta;

  HandState({this.stacks, this.button, this.sb}) {
    pot = 0;
    board = [];
    bettingRounds = [[]];
    infors = [
      for (int i = 0; i < stacks.length; i++) Status(_Status.hasntActed, 0)
    ];
    currentRaiseDelta = 0;
  }

  @override
  String toString() {
    final rounds = ["Preflop", "Flop", "Turn", "River"];
    final currentRound = bettingRounds.length - 1;

    String output = '''Handstate\n \
        \tbutton: seat $button\n\
        \tpot: $pot\n\
        \tcurrent round: ${rounds[currentRound]}\n\
        \tboard: ${board.join(' ')}\n\
        \tstacks: $stacks\n''';

    for (var item in bettingRounds.asMap().entries) {
      final i = item.key;
      final round = item.value;
      output += '\t${rounds[i]}';
      for (var action in round) {
        output += '\t\tseat ${action.seat}: $action';
      }
    }
    return output;
  }

  HandState withHistory(String historyString) {
    // Returns the HandState updated with a history string
    // and wrapped in Result<HandState, String>.

    // let mut hand = HandState.new(stacks, button, 5)
    //                         .with_history("P5 P10 R20 C20")
    // history string:
    // Actions 'R,C,F,K,P' followed by a number in case of R,C,P
    // separated by a space or pretty much anything.
    if (historyString == '') {
      return this;
    }
    final history = historyString.trim().split(' '); // TODO make a better split

    for (var actionString in history) {
      final action = Action.fromString(actionString);
      if (action == null) {
        throw FormatException('invalid action string: $actionString');
      }
      if (!isLegal(action)) {
        throw FormatException('illegal action: $actionString');
      }
      performAction(action);
      if (isFinished()) {
        break;
      }
      if (isRoundFinished()) {
        startNewRound();
      }
    }
    return this;
  }

  void performAction(Action action) {
    // assumes action is legal
    final seat = whosNext();

    switch (action.action) {
      case RawAction.fold:
        _performFold(seat);
        break;
      case RawAction.post:
        _performPost(seat, action.amount);
        break;
      case RawAction.call:
        _performCall(seat, action.amount);
        break;
      case RawAction.raise:
        _performRaise(seat, action.amount);
        break;
    }
    // TODO the less than part is temporary for development
    if (stacks[seat] <= 0) {
      infors[seat] = Status.allinfor(infors[seat].amount);
    }
    final round = bettingRounds.last;
    round.add(Action(action.action, action.amount, seat: seat));
    // TODO consider where to start new round
    // It may be better to start it somewhere else so
    // that we can add board cards at that point.
    // If we do it here then it may be less convenient to
    // figure out if we need to add board cards.
    // Maybe a function is_new_round{is_current_round_empty()}
  }

  void _performFold(int seat) {
    infors[seat] = Status.out();
  }

  void _performPost(int seat, int amount) {
    stacks[seat] -= amount;
    pot += amount;
    currentRaiseDelta = amount;
    infors[seat] = Status.hasntActed(amount);
  }

  void _performCall(int seat, int amount) {
    stacks[seat] -= amount;
    pot += amount;
    infors[seat] = infors[seat].incr(amount);
  }

  void _performRaise(int seat, int amount) {
    stacks[seat] -= amount;
    pot += amount;
    final infor = infors[seat].incr(amount);
    final increase = infor.amount - maxInfor();
    // the conditional covers allin where the raise
    // may be for less than the legal amount
    if (increase > currentRaiseDelta) {
      currentRaiseDelta = increase;
    }
    infors[seat] = infor;
  }

  void startNewRound() {
    currentRaiseDelta = 0;
    bettingRounds.add([]);
    infors = infors.map((e) {
      switch (e.status) {
        case _Status.infor:
          return Status.hasntActed(0);
        case _Status.allinfor:
          return Status.allinfor(0);
        case _Status.out:
          return Status.out();
        case _Status.hasntActed:
          throw FormatException(
              'There was a hasnt acted on start new round:\n $infors\n$this');
      }
    }).toList();
  }

  List<Action> legalActions() {
    // assume the current round is still in progress.
    final previous = previousNonFold();
    final bb = sb * 2;

    // handle blind posting
    if (roundNum() == 0) {
      if (previous == null) {
        return [Action.post(sb)];
      }
      if (previous == Action.post(sb)) {
        return [Action.post(bb)];
      }
    }
    if (previous == Action.call(0)) {
      return [Action.call(0), Action.raise(bb)];
    }
    // first postflop
    if (previous == null) {
      return [Action.call(0), Action.raise(bb)];
    }
    // the big blind faces no raise
    if (previous.amount <= bb && onBb()) {
      return [Action.call(0), Action.raise(bb)];
    }
    // now for call or raise an amount
    final call = amountToCall();
    final raise = call + currentRaiseDelta;
    return [Action.fold(), Action.call(call), Action.raise(raise)];
  }

  bool isLegal(Action action) {
    final amount = action.amount;
    switch (action.action) {
      case RawAction.fold:
        return isFoldLegal();
      case RawAction.post:
        return isPostLegal(amount);
      case RawAction.call:
        return (amount == 0) ? isCheckLegal() : isCallLegal(amount);
      case RawAction.raise:
        return isRaiseLegal(amount);
    }
    return null;
  }

  // @TODO is_<not post>_legal assumes you are not posting
  // keep in touch
  bool isCheckLegal() {
    final previous = previousNonFold();
    return (previous == null) ||
        (previous == Action.call(0)) ||
        (onBb() &&
            (previous.action == RawAction.call) &&
            // @TODO this will return the wrong value if
            // someone raises all in for 1.5 bbs and the
            // sb calls.  Maybe resort to max_infor or...?
            (previous.amount <= sb * 2));
  }

  bool isFoldLegal() {
    if (onBb()) {
      return maxInfor() > 2 * sb;
    }
    final previous = bettingRounds.last;
    return (previous.isNotEmpty) &&
        (previous.last != Action.call(0)) &&
        (previous.last != Action.post(sb));
  }

  bool isCallLegal(int amount) {
    // you can always call!
    return amount == amountToCall();
  }

  bool isRaiseLegal(int amount) {
    // you can always raise!
    return amount >= amountToCall() + currentRaiseDelta;
  }

  bool isPostLegal(int amount) {
    final nSmalls = amount.toDouble() / sb.toDouble();
    return (bettingRounds.length == 1) &&
        (bettingRounds[0].length.toDouble() == nSmalls - 1);
  }

  int amountToCall() {
    // 1. to call you must match the difference between the max infor
    //    and your infor.
    // 2. then the raise is the difference between the max infor
    //    and the player that max_infor_player raised.
    //    - you must ignore any allin-for-too-small-for-a-raise
    //      bets along the way
    //    - we keep track of current_raise_delta to help out
    return maxInfor() - infors[whosNext()].amount;
  }

  bool isRoundFinished() {
    // a round is finished when
    // 1. everyone has acted at least once
    //     exception:  bb preflop must act twice (including posting)
    // 2. the current player is infor the amount of the current maximum bet

    // this already filter players who are out or folded
    final status = infors[whosNext()];
    return status.status == _Status.infor && status.amount >= maxInfor();
  }

  bool isFinished() {
    return isRoundFinished() && roundNum() == RIVER;
  }

  bool isNewRound() {
    return bettingRounds.last.isEmpty;
  }

  int whosNext() {
    final round = bettingRounds.last;
    // We pretend the button acted last in a new round so that
    // it will now be one left of the button's turn.
    final previousSeat = (round.isEmpty) ? button : round.last.seat;
    // step though infors starting with previous seat + 1
    // until we find a player not with Status::Out
    for (var i = previousSeat + 1; i <= infors.length + previousSeat; i++) {
      var index = i % infors.length;
      if (infors[index].isActive()) {
        return index;
      }
    }
    return null;
  }

  bool onBb() {
    return infors[whosNext()] == Status.hasntActed(sb * 2);
  }

  int maxInfor() {
    final max = (Status previousValue, Status element) =>
        (element > previousValue) ? element : previousValue;
    return infors.reduce(max).amount;
  }

  int roundNum() {
    return bettingRounds.length - 1;
  }

  Action previousNonFold() {
    return bettingRounds.last.reversed.firstWhere(
        (element) => element.action != RawAction.fold,
        orElse: () => null);
  }
}

//------------------------------------------------------------------------

enum _Status {
  out,
  hasntActed, // this field is for blind posters
  infor,
  allinfor,
}

class Status {
  final _Status status;
  final int amount;
  Status(this.status, this.amount);

  @override
  String toString() {
    return '$status $amount';
  }

  static Status infor(int amount) {
    return Status(_Status.infor, amount);
  }

  static Status allinfor(int amount) {
    return Status(_Status.allinfor, amount);
  }

  static Status out() {
    return Status(_Status.out, 0);
  }

  static Status hasntActed(int amount) {
    return Status(_Status.hasntActed, amount);
  }

  @override
  bool operator ==(Object other) {
    return other is Status && status == other.status && amount == other.amount;
  }

  @override
  int get hashCode
      // we wont use this
      => amount % 1000 + 1000 * status.index;

  bool operator >(Status other) {
    return amount > other.amount;
  }

  bool operator <(Status other) {
    return amount < other.amount;
  }

  Status incr(int incrBy) {
    switch (status) {
      case _Status.infor:
        return Status.infor(incrBy + amount);
      case _Status.hasntActed:
        return Status.infor(incrBy + amount);
      default:
        throw FormatException("Can't incr Status Out or Allinfor");
    }
  }

  bool isActive() {
    return (status == _Status.hasntActed) || (status == _Status.infor);
  }
}

//------------------------------------------------------------------------

enum RawAction {
  fold,
  call,
  raise,
  post,
}

class Action {
  final RawAction action;
  final int amount;
  final int seat;

  Action(this.action, this.amount, {this.seat});

  @override
  String toString() {
    switch (action) {
      case RawAction.fold:
        return 'Fold';
      case RawAction.call:
        return ((amount ?? 0) == 0) ? 'Check' : 'Call $amount';
      case RawAction.raise:
        return 'Raise $amount';
      case RawAction.post:
        return 'Post $amount';
    }
    // so it doesn't yell at me
    return null;
  }

  @override
  bool operator ==(Object other) {
    return other is Action && action == other.action && amount == other.amount;
  }

  @override
  int get hashCode
      // we wont use this
      => amount % 1000 + 1000 * action.index;

  bool operator >(Action other) {
    return amount > other.amount;
  }

  bool operator <(Action other) {
    return amount < other.amount;
  }

  static Action fold({seat}) {
    return Action(RawAction.fold, 0, seat: seat);
  }

  static Action call(int amount, {seat}) {
    return Action(RawAction.call, amount, seat: seat);
  }

  static Action raise(int amount, {seat}) {
    return Action(RawAction.raise, amount, seat: seat);
  }

  static Action post(int amount, {seat}) {
    return Action(RawAction.post, amount, seat: seat);
  }

  static Action fromString(String string) {
    const actionChars = 'RCFPKB';
    const withAmounts = 'RCPB';

    if (string.isEmpty) {
      return null;
    }
    if (!actionChars.contains(string[0])) {
      return null;
    }
    var amount = 0;
    if (withAmounts.contains(string[0])) {
      amount = int.tryParse(string.substring(1));
      if (amount == null) {
        return null;
      }
    }
    Action action;
    switch (string[0]) {
      case 'B':
      case 'R':
        action = Action.raise(amount);
        break;
      case 'K':
      case 'C':
        action = Action.call(amount);
        break;
      case 'F':
        action = Action.fold();
        break;
      case 'P':
        action = Action.post(amount);
        break;
      default:
        action = null;
    }
    return action;
  }
}
