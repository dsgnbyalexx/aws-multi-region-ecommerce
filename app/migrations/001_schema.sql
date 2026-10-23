-- Money is stored as integer cents, never floating point, to avoid rounding errors.
CREATE TABLE products (
  id           SERIAL PRIMARY KEY,
  sku          TEXT        NOT NULL UNIQUE,
  name         TEXT        NOT NULL,
  description  TEXT        NOT NULL DEFAULT '',
  price_cents  INTEGER     NOT NULL CHECK (price_cents >= 0),
  stock        INTEGER     NOT NULL CHECK (stock >= 0),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE orders (
  id              SERIAL PRIMARY KEY,
  customer_email  TEXT        NOT NULL,
  total_cents     INTEGER     NOT NULL CHECK (total_cents >= 0),
  status          TEXT        NOT NULL DEFAULT 'confirmed',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE order_items (
  order_id          INTEGER NOT NULL REFERENCES orders (id) ON DELETE CASCADE,
  product_id        INTEGER NOT NULL REFERENCES products (id),
  quantity          INTEGER NOT NULL CHECK (quantity > 0),
  unit_price_cents  INTEGER NOT NULL CHECK (unit_price_cents >= 0),
  PRIMARY KEY (order_id, product_id)
);

CREATE INDEX order_items_product_id_idx ON order_items (product_id);
