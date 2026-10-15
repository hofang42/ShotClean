/// Decision taken on one card in swipe mode (S7). Only queues; nothing is deleted here.
enum SwipeAction: Equatable {
  case keep
  case delete
}
