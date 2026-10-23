import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseId, validateOrder, MAX_ITEMS, MAX_QUANTITY } from '../../src/validation.js';

const valid = { customerEmail: 'Ada@Example.com', items: [{ productId: 1, quantity: 2 }] };

test('accepts a valid order and normalises the email', () => {
  const r = validateOrder(valid);
  assert.equal(r.ok, true);
  assert.equal(r.value.customerEmail, 'ada@example.com');
  assert.deepEqual(r.value.items, [{ productId: 1, quantity: 2 }]);
});

test('strips unexpected fields from items', () => {
  const r = validateOrder({ ...valid, items: [{ productId: 1, quantity: 1, priceCents: 0 }] });
  assert.deepEqual(r.value.items, [{ productId: 1, quantity: 1 }]);
});

test('rejects non-object bodies', () => {
  for (const body of [null, [], 'text', 42]) {
    assert.equal(validateOrder(body).ok, false);
  }
});

test('rejects missing or malformed email', () => {
  for (const customerEmail of [undefined, '', 'not-an-email', 'a@b', `${'x'.repeat(250)}@x.com`]) {
    assert.equal(validateOrder({ ...valid, customerEmail }).ok, false, `email: ${customerEmail}`);
  }
});

test('rejects empty, missing and oversized item lists', () => {
  assert.equal(validateOrder({ ...valid, items: [] }).ok, false);
  assert.equal(validateOrder({ customerEmail: valid.customerEmail }).ok, false);
  const tooMany = Array.from({ length: MAX_ITEMS + 1 }, (_, i) => ({ productId: i + 1, quantity: 1 }));
  assert.equal(validateOrder({ ...valid, items: tooMany }).ok, false);
});

test('rejects bad quantities', () => {
  for (const quantity of [0, -1, 1.5, '2', MAX_QUANTITY + 1, null]) {
    assert.equal(validateOrder({ ...valid, items: [{ productId: 1, quantity }] }).ok, false, `qty: ${quantity}`);
  }
});

test('rejects bad and duplicate product ids', () => {
  for (const productId of [0, -3, 2.5, '1', 2147483648]) {
    assert.equal(validateOrder({ ...valid, items: [{ productId, quantity: 1 }] }).ok, false, `id: ${productId}`);
  }
  const dup = validateOrder({ ...valid, items: [{ productId: 1, quantity: 1 }, { productId: 1, quantity: 2 }] });
  assert.equal(dup.ok, false);
  assert.match(dup.errors.join(), /duplicated/);
});

test('parseId accepts only positive integers within INTEGER range', () => {
  assert.equal(parseId('1'), 1);
  assert.equal(parseId('2147483647'), 2147483647);
  for (const raw of ['0', '-1', '01', '1.5', 'abc', '', '2147483648', '99999999999', undefined]) {
    assert.equal(parseId(raw), null, `raw: ${raw}`);
  }
});
