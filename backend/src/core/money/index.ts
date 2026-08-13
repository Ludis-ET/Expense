/**
 * The money core.
 *
 * `ledger` holds the arithmetic and the invariants, and knows nothing about a
 * database. `balances` is the only code that reads money out of Postgres.
 * `postings` is the only code that writes it. `lock` serialises those writes per
 * user, and `reconcile` proves - or repairs - the result.
 *
 * Everything else in the app is a caller.
 */
export {
  ZERO,
  dec,
  sum,
  sameMoney,
  pairKey,
  splitPair,
  realBalances,
  heldByPair,
  heldByAccount,
  potByBudget,
  availableByAccount,
  sharesOfBudget,
  readyToAssign as computeReadyToAssign,
  snapshot,
  checkInvariants,
  excessReservation,
  type Money,
  type CashRow,
  type HoldRow,
  type PlanSpendRow,
  type AccountSeed,
  type LedgerSnapshot,
  type Violation,
  type InvariantCode,
} from './ledger.js';

export {
  loadSnapshot,
  realOf,
  heldOf,
  availableOf,
  potOf,
  heldFor,
  sharesOf,
  readyToAssign,
  lockedTotal,
  realTotal,
  accountFigures,
  type SnapshotOptions,
} from './balances.js';

export { withMoneyLock, type MoneyTx } from './lock.js';

export {
  postTransaction,
  patchTransaction,
  deleteTransaction,
  fundPlan,
  releasePlan,
  movePlanMoney,
  moveReservation,
  adjustPlan,
  fundedThisCycle,
  assertSound,
  type Cover,
  type PostTransactionInput,
  type PatchTransactionInput,
  type ShortfallDetails,
} from './postings.js';

export { inspect, repair, inspectAll, type DriftReport, type RepairResult, type RepairAction } from './reconcile.js';
