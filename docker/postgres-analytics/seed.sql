-- Analytics Database Seed Data
-- Populates sample data for development and testing.

-- ============================================================
-- Customers
-- ============================================================

INSERT INTO customers (first_name, last_name, email, city, country) VALUES
('Alice',   'Johnson',  'alice.johnson@example.com',   'New York',      'US'),
('Bob',     'Smith',    'bob.smith@example.com',       'Los Angeles',   'US'),
('Charlie', 'Williams', 'charlie.williams@example.com','Chicago',       'US'),
('Diana',   'Brown',    'diana.brown@example.com',     'Houston',       'US'),
('Eve',     'Davis',    'eve.davis@example.com',       'Phoenix',       'US'),
('Frank',   'Miller',   'frank.miller@example.com',    'Philadelphia',  'US'),
('Grace',   'Wilson',   'grace.wilson@example.com',    'San Antonio',   'US'),
('Henry',   'Moore',    'henry.moore@example.com',     'San Diego',     'US'),
('Ivy',     'Taylor',   'ivy.taylor@example.com',      'Dallas',        'US'),
('Jack',    'Anderson', 'jack.anderson@example.com',   'San Jose',      'US'),
('Karen',   'Thomas',   'karen.thomas@example.com',    'London',        'UK'),
('Leo',     'Martinez', 'leo.martinez@example.com',    'Toronto',       'CA'),
('Mia',     'Garcia',   'mia.garcia@example.com',      'Sydney',        'AU'),
('Noah',    'Robinson', 'noah.robinson@example.com',   'Berlin',        'DE'),
('Olivia',  'Clark',    'olivia.clark@example.com',    'Paris',         'FR');

-- ============================================================
-- Products
-- ============================================================

INSERT INTO products (name, category, price, stock_qty, is_active) VALUES
('Wireless Mouse',         'Electronics',  29.99,  150, true),
('Mechanical Keyboard',    'Electronics',  89.99,  75,  true),
('USB-C Hub',              'Electronics',  49.99,  200, true),
('Standing Desk',          'Furniture',    499.99, 30,  true),
('Ergonomic Chair',        'Furniture',    349.99, 45,  true),
('Monitor Arm',            'Furniture',    79.99,  120, true),
('Notebook A5',            'Stationery',   12.99,  500, true),
('Gel Pen Set',            'Stationery',   8.99,   300, true),
('Desk Lamp',              'Lighting',     45.99,  90,  true),
('Webcam HD',              'Electronics',  69.99,  60,  true),
('Noise Cancelling Headphones', 'Electronics', 199.99, 40, true),
('Laptop Stand',           'Furniture',    39.99,  110, true),
('Cable Management Kit',   'Accessories',  19.99,  250, true),
('Whiteboard Markers',     'Stationery',   6.99,   400, true),
('Discontinued Widget',    'Electronics',  9.99,   0,   false);

-- ============================================================
-- Orders (spanning last 6 months for temporal query testing)
-- ============================================================

INSERT INTO orders (customer_id, status, total_amount, order_date, shipped_date) VALUES
-- Recent orders (this month)
(1,  'completed',  119.98, now() - interval '2 days',   now() - interval '1 day'),
(2,  'completed',  89.99,  now() - interval '5 days',   now() - interval '3 days'),
(3,  'pending',    549.98, now() - interval '1 day',    NULL),
(4,  'shipped',    349.99, now() - interval '3 days',   now() - interval '1 day'),
(5,  'completed',  29.99,  now() - interval '7 days',   now() - interval '5 days'),
-- Last month
(6,  'completed',  129.98, now() - interval '35 days',  now() - interval '32 days'),
(7,  'completed',  499.99, now() - interval '40 days',  now() - interval '37 days'),
(8,  'cancelled',  89.99,  now() - interval '38 days',  NULL),
(1,  'completed',  45.99,  now() - interval '42 days',  now() - interval '39 days'),
(9,  'completed',  79.99,  now() - interval '30 days',  now() - interval '27 days'),
-- 2-3 months ago
(10, 'completed',  199.99, now() - interval '65 days',  now() - interval '62 days'),
(11, 'completed',  69.99,  now() - interval '70 days',  now() - interval '67 days'),
(2,  'completed',  39.99,  now() - interval '75 days',  now() - interval '72 days'),
(12, 'completed',  849.98, now() - interval '80 days',  now() - interval '77 days'),
(3,  'returned',   29.99,  now() - interval '60 days',  now() - interval '57 days'),
-- 3-6 months ago
(13, 'completed',  139.98, now() - interval '100 days', now() - interval '97 days'),
(14, 'completed',  519.98, now() - interval '120 days', now() - interval '117 days'),
(15, 'completed',  89.99,  now() - interval '130 days', now() - interval '127 days'),
(4,  'completed',  259.98, now() - interval '150 days', now() - interval '147 days'),
(5,  'completed',  12.99,  now() - interval '160 days', now() - interval '157 days'),
(6,  'completed',  349.99, now() - interval '170 days', now() - interval '167 days'),
(7,  'completed',  49.99,  now() - interval '180 days', now() - interval '177 days');

-- ============================================================
-- Order Items
-- ============================================================

INSERT INTO order_items (order_id, product_id, quantity, unit_price, total_price) VALUES
-- Order 1: Wireless Mouse + Mechanical Keyboard
(1,  1,  1, 29.99,  29.99),
(1,  2,  1, 89.99,  89.99),
-- Order 2: Mechanical Keyboard
(2,  2,  1, 89.99,  89.99),
-- Order 3: Standing Desk + USB-C Hub
(3,  4,  1, 499.99, 499.99),
(3,  3,  1, 49.99,  49.99),
-- Order 4: Ergonomic Chair
(4,  5,  1, 349.99, 349.99),
-- Order 5: Wireless Mouse
(5,  1,  1, 29.99,  29.99),
-- Order 6: Monitor Arm + USB-C Hub
(6,  6,  1, 79.99,  79.99),
(6,  3,  1, 49.99,  49.99),
-- Order 7: Standing Desk
(7,  4,  1, 499.99, 499.99),
-- Order 8: Mechanical Keyboard (cancelled)
(8,  2,  1, 89.99,  89.99),
-- Order 9: Desk Lamp
(9,  9,  1, 45.99,  45.99),
-- Order 10: Monitor Arm
(10, 6,  1, 79.99,  79.99),
-- Order 11: Noise Cancelling Headphones
(11, 11, 1, 199.99, 199.99),
-- Order 12: Webcam HD
(12, 10, 1, 69.99,  69.99),
-- Order 13: Laptop Stand
(13, 12, 1, 39.99,  39.99),
-- Order 14: Standing Desk + Ergonomic Chair
(14, 4,  1, 499.99, 499.99),
(14, 5,  1, 349.99, 349.99),
-- Order 15: Noise Cancelling Headphones
(15, 11, 1, 139.98, 139.98),
-- Order 16: Standing Desk + Cable Management Kit
(16, 4, 1, 499.99, 499.99),
(16, 13, 1, 19.99,  19.99),
-- Order 17: Mechanical Keyboard
(17, 2,  1, 89.99,  89.99),
-- Order 18: Ergonomic Chair + Monitor Arm
(18, 5,  1, 349.99, 349.99),
(18, 6,  1, 79.99,  79.99),
(18, 13, 2, 19.99,  39.98),
-- Order 19: Notebook A5
(19, 7,  1, 12.99,  12.99),
-- Order 20: Ergonomic Chair
(20, 5,  1, 349.99, 349.99),
-- Order 21: USB-C Hub
(21, 3,  1, 49.99,  49.99),
-- Order 22: Webcam HD + Wireless Mouse
(22, 10, 1, 69.99,  69.99),
(22, 1,  1, 29.99,  29.99);
