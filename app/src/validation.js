const MAX_INT4 = 2147483647; // largest value a PostgreSQL INTEGER column can hold
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
export const MAX_ITEMS = 20;
export const MAX_QUANTITY = 10;

// Parses a URL path id such as "42". Returns a number, or null if invalid.
export function parseId(raw) {
  if (typeof raw !== 'string' || !/^[1-9]\d{0,9}$/.test(raw)) return null;
  const id = Number(raw);
  return id <= MAX_INT4 ? id : null;
}

function isPositiveInt(value, max) {
  return Number.isInteger(value) && value >= 1 && value <= max;
}

// Validates an order request body. Never trust client input: everything the
// database relies on is checked here before any query runs.
export function validateOrder(body) {
  const errors = [];

  if (body === null || typeof body !== 'object' || Array.isArray(body)) {
    return { ok: false, errors: ['body must be a JSON object'] };
  }

  const { customerEmail, items } = body;

  if (typeof customerEmail !== 'string' || customerEmail.length > 254 || !EMAIL_RE.test(customerEmail)) {
    errors.push('customerEmail must be a valid email address');
  }

  if (!Array.isArray(items) || items.length === 0 || items.length > MAX_ITEMS) {
    errors.push(`items must be an array of 1 to ${MAX_ITEMS} entries`);
  } else {
    const seen = new Set();
    items.forEach((item, i) => {
      if (item === null || typeof item !== 'object') {
        errors.push(`items[${i}] must be an object`);
        return;
      }
      if (!isPositiveInt(item.productId, MAX_INT4)) {
        errors.push(`items[${i}].productId must be a positive integer`);
      } else if (seen.has(item.productId)) {
        errors.push(`items[${i}].productId is duplicated; combine quantities instead`);
      } else {
        seen.add(item.productId);
      }
      if (!isPositiveInt(item.quantity, MAX_QUANTITY)) {
        errors.push(`items[${i}].quantity must be an integer from 1 to ${MAX_QUANTITY}`);
      }
    });
  }

  if (errors.length > 0) return { ok: false, errors };

  return {
    ok: true,
    value: {
      customerEmail: customerEmail.toLowerCase(),
      items: items.map(({ productId, quantity }) => ({ productId, quantity })),
    },
  };
}
