-- Demo catalogue. ON CONFLICT makes this safe to run more than once.
INSERT INTO products (sku, name, description, price_cents, stock) VALUES
  ('MUG-001',  'Cloud Mug',            'Ceramic mug for long deploy nights.',        1499, 40),
  ('TEE-001',  'YAML Engineer Tee',    'Soft cotton tee. Indentation sold separately.', 2499, 25),
  ('STK-001',  'Terraform Sticker Pack','Six vinyl stickers for your laptop lid.',     599, 100),
  ('HOD-001',  'On-Call Hoodie',       'Warm hoodie for 3 a.m. pages.',              4999, 10),
  ('BTL-001',  'Kubernetes Bottle',    'Insulated bottle that self-heals (not really).', 1999, 30),
  ('NBK-001',  'Runbook Notebook',     'Dotted notebook for incident notes.',         899, 60)
ON CONFLICT (sku) DO NOTHING;
