/**
 * Unbiased Fisher-Yates (Knuth) array shuffle and cycle-safe ShuffleBag.
 */

/**
 * Fisher-Yates (Knuth) unbiased array shuffle.
 * Returns a new shuffled array without mutating the input.
 */
export function fisherYatesShuffle<T>(items: readonly T[], randomFn: () => number = Math.random): T[] {
  const result = [...items];
  for (let i = result.length - 1; i > 0; i--) {
    const j = Math.floor(randomFn() * (i + 1));
    const temp = result[i]!;
    result[i] = result[j]!;
    result[j] = temp;
  }
  return result;
}

export interface ShuffleBagOptions<T> {
  getId?: (item: T) => string | number;
  randomFn?: () => number;
}

/**
 * ShuffleBag implements a randomized playback cycle:
 * 1. Shuffles the full available item set using Fisher-Yates.
 * 2. Yields each item exactly once per cycle.
 * 3. Once exhausted, reshuffles.
 * 4. If length > 1, guarantees the first item of the new cycle is not the same
 *    as the last item of the previous cycle.
 * 5. Handles 0 and 1 items gracefully.
 */
export class ShuffleBag<T> {
  private items: readonly T[] = [];
  private bag: T[] = [];
  private lastItem: T | undefined = undefined;
  private readonly getId: (item: T) => string | number;
  private readonly randomFn: () => number;

  constructor(items: readonly T[] = [], options?: ShuffleBagOptions<T>) {
    this.getId = options?.getId ?? ((item: any) => item?.id ?? item);
    this.randomFn = options?.randomFn ?? Math.random;
    this.setItems(items);
  }

  public setItems(items: readonly T[]): void {
    this.items = [...items];
    this.bag = [];
    this.lastItem = undefined;
    if (this.items.length > 0) {
      this.refill();
    }
  }

  private refill(): void {
    if (this.items.length === 0) {
      this.bag = [];
      return;
    }
    if (this.items.length === 1) {
      this.bag = [...this.items];
      return;
    }

    const nextBag = fisherYatesShuffle(this.items, this.randomFn);

    // If there is more than 1 item and we have a lastItem from the previous cycle,
    // ensure the new cycle does not start with the same item as the previous cycle's end.
    if (this.lastItem !== undefined && this.items.length > 1) {
      const lastId = this.getId(this.lastItem);
      if (this.getId(nextBag[0]!) === lastId) {
        // Swap with a randomly chosen element from indices 1..length-1
        const swapIdx = 1 + Math.floor(this.randomFn() * (nextBag.length - 1));
        const temp = nextBag[0]!;
        nextBag[0] = nextBag[swapIdx]!;
        nextBag[swapIdx] = temp;
      }
    }

    this.bag = nextBag;
  }

  /**
   * Advances and returns the next item in the cycle.
   */
  public next(): T | undefined {
    if (this.items.length === 0) {
      return undefined;
    }
    if (this.bag.length === 0) {
      this.refill();
    }
    const item = this.bag.shift();
    this.lastItem = item;
    return item;
  }

  /**
   * Returns the currently active item, if any.
   */
  public current(): T | undefined {
    return this.lastItem;
  }

  /**
   * Returns the total item count in the underlying collection.
   */
  public size(): number {
    return this.items.length;
  }

  /**
   * Returns the remaining unconsumed items count in the current cycle.
   */
  public remaining(): number {
    return this.bag.length;
  }
}
