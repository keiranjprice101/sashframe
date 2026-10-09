import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { fisherYatesShuffle, ShuffleBag } from '../src/lib/shuffle.ts';

describe('Fisher-Yates Shuffle', () => {
  test('empty array returns a new empty array', () => {
    const input: string[] = [];
    const result = fisherYatesShuffle(input);
    assert.deepEqual(result, []);
    assert.notEqual(result, input);
  });

  test('single item array returns single item', () => {
    const input = ['photo1'];
    const result = fisherYatesShuffle(input);
    assert.deepEqual(result, ['photo1']);
  });

  test('shuffled array preserves all elements and count without duplication or loss', () => {
    const input = ['a', 'b', 'c', 'd', 'e', 'f', 'g'];
    const result = fisherYatesShuffle(input);
    assert.equal(result.length, input.length);
    assert.deepEqual([...result].sort(), [...input].sort());
  });

  test('deterministic pseudo-random function shuffles as expected', () => {
    // Constant random generator returning middle values
    const fakeRandom = () => 0.5;
    const input = [1, 2, 3, 4];
    const result = fisherYatesShuffle(input, fakeRandom);
    assert.equal(result.length, 4);
    assert.deepEqual([...result].sort(), [1, 2, 3, 4]);
  });
});

describe('ShuffleBag', () => {
  test('empty collection handles next() and current() gracefully', () => {
    const bag = new ShuffleBag<string>([]);
    assert.equal(bag.size(), 0);
    assert.equal(bag.next(), undefined);
    assert.equal(bag.current(), undefined);
    assert.equal(bag.remaining(), 0);
  });

  test('single item collection cycles cleanly without error', () => {
    const bag = new ShuffleBag<string>(['only-photo']);
    assert.equal(bag.size(), 1);

    for (let i = 0; i < 5; i++) {
      const item = bag.next();
      assert.equal(item, 'only-photo');
      assert.equal(bag.current(), 'only-photo');
    }
  });

  test('multiple items: each item appears exactly once per cycle', () => {
    const items = [
      { id: 'p1', name: 'Photo 1' },
      { id: 'p2', name: 'Photo 2' },
      { id: 'p3', name: 'Photo 3' },
      { id: 'p4', name: 'Photo 4' },
      { id: 'p5', name: 'Photo 5' },
    ];
    const bag = new ShuffleBag(items, { getId: (p) => p.id });

    // Test across 3 complete cycles
    for (let cycle = 0; cycle < 3; cycle++) {
      const seenIds: string[] = [];
      for (let i = 0; i < items.length; i++) {
        const photo = bag.next();
        assert.ok(photo, 'Photo must not be undefined');
        seenIds.push(photo.id);
      }

      assert.equal(seenIds.length, items.length);
      // Verify all items appeared exactly once in this cycle
      const uniqueSeen = new Set(seenIds);
      assert.equal(uniqueSeen.size, items.length);
      assert.deepEqual([...uniqueSeen].sort(), items.map(p => p.id).sort());
    }
  });

  test('multiple items: cycle boundary avoids repeating the same photo across consecutive cycles', () => {
    const items = [
      { id: 'a' },
      { id: 'b' },
      { id: 'c' },
    ];

    // Force a predictable collision scenario:
    // When random generator returns 0, shuffle produces reverse order.
    // If the next cycle starts with the last element of the previous cycle,
    // the boundary guard must swap it.
    let step = 0;
    // Sequence generator that produces alternating shuffles
    const scriptedRandom = () => {
      step++;
      return (step % 2 === 0) ? 0.999 : 0.001;
    };

    const bag = new ShuffleBag(items, {
      getId: (x) => x.id,
      randomFn: scriptedRandom,
    });

    let previousItem: { id: string } | undefined = undefined;

    // Run across 20 consecutive transitions (spanning multiple cycle boundaries)
    for (let i = 0; i < 30; i++) {
      const current = bag.next();
      assert.ok(current);
      if (previousItem !== undefined) {
        // When length > 1, consecutive items across ANY step (including cycle boundaries)
        // must not be identical!
        assert.notEqual(
          current.id,
          previousItem.id,
          `Item '${current.id}' repeated immediately at step ${i}`
        );
      }
      previousItem = current;
    }
  });

  test('setItems dynamically updates collection and resets cycle', () => {
    const bag = new ShuffleBag<string>(['a', 'b']);
    assert.equal(bag.size(), 2);
    const first = bag.next();
    assert.ok(first === 'a' || first === 'b');

    // Replace with new items
    bag.setItems(['x', 'y', 'z']);
    assert.equal(bag.size(), 3);
    const seen = new Set<string>();
    for (let i = 0; i < 3; i++) {
      seen.add(bag.next()!);
    }
    assert.deepEqual(seen, new Set(['x', 'y', 'z']));
  });
});
