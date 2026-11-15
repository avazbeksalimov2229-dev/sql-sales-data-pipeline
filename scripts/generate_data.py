"""Generate the synthetic sales dataset used by the SQL pipeline and the Power BI dashboard.

The company ("Harbor & Pine Supply Co.") is fictional. The script writes two versions:

  data/raw/       messy exports, the way an ERP / e-commerce system really delivers them
  data/expected/  what the clean tables must look like after the SQL pipeline (answer key)

The seed is fixed, so every run produces exactly the same files.

Usage:
    python generate_data.py [project_dir]      (default: ..)
"""
import csv
import math
import random
import sys
from datetime import date, datetime, timedelta
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path

random.seed(2024)

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
RAW = ROOT / "data" / "raw"
EXP = ROOT / "data" / "expected"
RAW.mkdir(parents=True, exist_ok=True)
EXP.mkdir(parents=True, exist_ok=True)

START, END = date(2024, 1, 1), date(2026, 6, 30)
CENT = Decimal("0.01")


def money(x):
    return Decimal(str(x)).quantize(CENT, rounding=ROUND_HALF_UP)


def write_csv(path, header, rows):
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(header)
        w.writerows(rows)
    print(f"{path.parent.name}/{path.name:<26}{len(rows):>8,} rows")


def weighted(items, weights):
    return random.choices(items, weights=weights, k=1)[0]


# --------------------------------------------------------------------------
# Geography and sales team
# --------------------------------------------------------------------------
STATES = [
    # code, name, region, weight, cities, dirty aliases
    ("CA", "California", "West", 12, ["Los Angeles", "San Diego", "San Jose"], ["California", "Calif.", " ca"]),
    ("WA", "Washington", "West", 3, ["Seattle", "Spokane"], ["Washington", "Wash."]),
    ("OR", "Oregon", "West", 2, ["Portland"], ["Oregon", "Ore."]),
    ("AZ", "Arizona", "West", 3, ["Phoenix", "Tucson"], ["Arizona", "Ariz."]),
    ("CO", "Colorado", "West", 3, ["Denver"], ["Colorado", "Colo."]),
    ("NV", "Nevada", "West", 2, ["Las Vegas"], ["Nevada", "Nev."]),
    ("UT", "Utah", "West", 2, ["Salt Lake City"], ["Utah"]),
    ("TX", "Texas", "Central", 9, ["Houston", "Dallas", "Austin"], ["Texas", "Tex.", "tx "]),
    ("IL", "Illinois", "Central", 4, ["Chicago"], ["Illinois", "Ill."]),
    ("MN", "Minnesota", "Central", 2, ["Minneapolis"], ["Minnesota", "Minn."]),
    ("MO", "Missouri", "Central", 2, ["St. Louis", "Kansas City"], ["Missouri"]),
    ("OH", "Ohio", "Central", 4, ["Columbus", "Cleveland"], ["Ohio"]),
    ("MI", "Michigan", "Central", 3, ["Detroit"], ["Michigan", "Mich."]),
    ("WI", "Wisconsin", "Central", 2, ["Milwaukee"], ["Wisconsin", "Wis."]),
    ("NY", "New York", "East", 6, ["New York", "Buffalo"], ["New York", "N.Y.", "ny"]),
    ("PA", "Pennsylvania", "East", 4, ["Philadelphia", "Pittsburgh"], ["Pennsylvania", "Penn."]),
    ("NJ", "New Jersey", "East", 3, ["Newark"], ["New Jersey", "N.J."]),
    ("MA", "Massachusetts", "East", 3, ["Boston"], ["Massachusetts", "Mass."]),
    ("VA", "Virginia", "East", 3, ["Richmond"], ["Virginia", "Va."]),
    ("NC", "North Carolina", "East", 3, ["Charlotte", "Raleigh"], ["North Carolina", "N.C."]),
    ("MD", "Maryland", "East", 2, ["Baltimore"], ["Maryland", "Md."]),
    ("FL", "Florida", "South", 7, ["Miami", "Orlando", "Tampa"], ["Florida", "Fla.", "fl"]),
    ("GA", "Georgia", "South", 3, ["Atlanta"], ["Georgia", "Ga."]),
    ("TN", "Tennessee", "South", 2, ["Nashville", "Memphis"], ["Tennessee", "Tenn."]),
    ("AL", "Alabama", "South", 2, ["Birmingham"], ["Alabama", "Ala."]),
    ("LA", "Louisiana", "South", 2, ["New Orleans"], ["Louisiana"]),
    ("SC", "South Carolina", "South", 2, ["Charleston"], ["South Carolina", "S.C."]),
    ("KY", "Kentucky", "South", 2, ["Louisville"], ["Kentucky", "Ky."]),
]
STATE = {s[0]: s for s in STATES}

REPS = [("SR01", "Dana Brooks", "West", date(2021, 3, 15)), ("SR02", "Miguel Torres", "West", date(2023, 8, 1)),
        ("SR03", "Rachel Kim", "Central", date(2020, 6, 1)), ("SR04", "Tom Becker", "Central", date(2022, 1, 10)),
        ("SR05", "Priya Shah", "East", date(2019, 9, 23)), ("SR06", "Kevin O'Neill", "East", date(2023, 2, 6)),
        ("SR07", "Marcus Hill", "South", date(2021, 11, 1)), ("SR08", "Elena Petrova", "South", date(2024, 4, 15))]
REPS_BY_REGION = {}
for r in REPS:
    REPS_BY_REGION.setdefault(r[2], []).append(r)

# --------------------------------------------------------------------------
# Products
# --------------------------------------------------------------------------
CATALOG = {
    ("Furniture", "FUR"): {
        ("Chairs", "CHA", 0.66): (["Mesh Office Chair", "Ergonomic Task Chair", "Executive Leather Chair", "Stacking Guest Chair", "Drafting Stool"], (89, 449)),
        ("Desks", "DSK", 0.62): (["Standing Desk", "Writing Desk", "L-Shaped Desk", "Compact Laptop Desk"], (149, 699)),
        ("Tables", "TBL", 0.72): (["Conference Table", "Folding Table", "Round Meeting Table", "Coffee Table"], (99, 899)),
        ("Storage", "STO", 0.60): (["Filing Cabinet", "Bookcase", "Mobile Pedestal", "Storage Cabinet"], (79, 389)),
    },
    ("Office Supplies", "OFF"): {
        ("Paper", "PAP", 0.55): (["Copy Paper Case", "Premium Printer Paper", "Recycled Paper Ream", "Sticky Notes Pack"], (6, 49)),
        ("Binders", "BIN", 0.48): (["Ring Binder", "Presentation Binder", "Binder Clips Box"], (3, 24)),
        ("Writing", "WRI", 0.50): (["Gel Pen Set", "Highlighter Pack", "Mechanical Pencil Set", "Whiteboard Markers"], (4, 29)),
        ("Organizers", "ORG", 0.54): (["Desk Organizer", "Document Tray", "Drawer Organizer"], (9, 45)),
        ("Labels", "LAB", 0.52): (["Shipping Labels", "File Folder Labels", "Label Maker Tape"], (8, 39)),
    },
    ("Technology", "TEC"): {
        ("Monitors", "MON", 0.84): (["24in Full HD Monitor", "27in QHD Monitor", "32in 4K Monitor", "Portable USB-C Monitor"], (149, 649)),
        ("Accessories", "ACC", 0.70): (["Wireless Mouse", "Mechanical Keyboard", "USB-C Hub", "HD Webcam", "Noise-Cancelling Headset"], (19, 189)),
        ("Printers", "PRN", 0.80): (["Laser Printer", "Inkjet All-in-One", "Label Printer"], (99, 499)),
        ("Networking", "NET", 0.76): (["Wi-Fi Router", "8-Port Network Switch", "Mesh Wi-Fi Kit"], (39, 329)),
        ("Phones", "PHO", 0.74): (["Desk IP Phone", "Conference Speakerphone"], (79, 299)),
    },
    ("Home & Decor", "HOM"): {
        ("Lighting", "LIG", 0.56): (["LED Desk Lamp", "Floor Lamp", "Pendant Light"], (24, 179)),
        ("Rugs", "RUG", 0.58): (["5x7 Area Rug", "Runner Rug", "Office Chair Mat"], (29, 229)),
        ("Kitchen", "KIT", 0.60): (["Coffee Maker", "Electric Kettle", "Water Dispenser"], (25, 219)),
        ("Decor", "DEC", 0.52): (["Wall Clock", "Framed Wall Art", "Artificial Plant"], (15, 119)),
    },
}
BRANDS = {"Furniture": ["ErgoLine", "Oakfield", "Northdesk"], "Office Supplies": ["PaperPro", "Clearwrite", "OfficeMate"],
          "Technology": ["Voltix", "Brightview", "Netcore"], "Home & Decor": ["Lumen", "Hearth", "Casa Verde"]}
VARIANTS = {"Furniture": ["Black", "Walnut", "White"], "Office Supplies": ["", "Bulk"], "Technology": ["", "Pro"],
            "Home & Decor": ["", "Large"]}


def nice_price(lo, hi):
    p = math.exp(random.uniform(math.log(lo), math.log(hi)))
    return float(int(p) + 0.99) if p >= 10 else round(p, 2)


products = []
for (cat, cat_code), subs in CATALOG.items():
    for (sub, sub_code, cost_ratio), (items, (lo, hi)) in subs.items():
        n = 0
        for item in items:
            for variant in random.sample(VARIANTS[cat], k=min(2, len(VARIANTS[cat]))):
                n += 1
                price = money(nice_price(lo, hi))
                cost = money(float(price) * min(max(random.gauss(cost_ratio, 0.03), 0.3), 0.95))
                name = f"{random.choice(BRANDS[cat])} {item}" + (f" {variant}" if variant else "")
                products.append({"product_id": f"{cat_code}-{sub_code}-{n:04d}", "product_name": name, "category": cat,
                                 "subcategory": sub, "unit_cost": cost, "list_price": price,
                                 "popularity": random.lognormvariate(0, 0.8)})
PROD = {p["product_id"]: p for p in products}

# products whose cost is missing in the raw export -> imputed by the pipeline
MISSING_COST = set(random.sample([p["product_id"] for p in products], 3))
for sub in {p["subcategory"] for p in products}:
    known = [p for p in products if p["subcategory"] == sub and p["product_id"] not in MISSING_COST]
    ratio = sum(Decimal(p["unit_cost"]) / Decimal(p["list_price"]) for p in known) / len(known)
    for p in products:
        if p["subcategory"] == sub and p["product_id"] in MISSING_COST:
            p["unit_cost"] = (p["list_price"] * ratio).quantize(CENT, rounding=ROUND_HALF_UP)
            p["cost_imputed"] = True

# --------------------------------------------------------------------------
# Customers
# --------------------------------------------------------------------------
FIRST = ["James", "Mary", "Robert", "Patricia", "John", "Jennifer", "Michael", "Linda", "David", "Elizabeth", "William",
         "Barbara", "Richard", "Susan", "Joseph", "Jessica", "Thomas", "Sarah", "Carlos", "Karen", "Daniel", "Lisa",
         "Matthew", "Nancy", "Anthony", "Sandra", "Mark", "Ashley", "Steven", "Emily", "Andrew", "Michelle", "Jose",
         "Amanda", "Ryan", "Melissa", "Kevin", "Laura", "Brian", "Hannah"]
LAST = ["Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis", "Rodriguez", "Martinez",
        "Hernandez", "Lopez", "Gonzalez", "Wilson", "Anderson", "Thomas", "Taylor", "Moore", "Jackson", "Martin", "Lee",
        "Perez", "Thompson", "White", "Harris", "Clark", "Lewis", "Robinson", "Walker", "Young", "Allen", "King",
        "Wright", "Scott", "Nguyen", "Hill", "Green", "Adams", "Baker", "Nelson"]
CO_ADJ = ["Summit", "Blue Ridge", "Ironwood", "Harbor", "Silverline", "Northstar", "Granite", "Cedar", "Pioneer",
          "Evergreen", "Brightpath", "Redwood", "Lakeside", "Keystone", "Atlas", "Riverbend", "Copperfield", "Sunrise"]
CO_NOUN = ["Logistics", "Dental", "Consulting", "Realty", "Architects", "Health", "Engineering", "Law Group",
           "Marketing", "Labs", "Builders", "Accounting", "Media", "Solutions", "Clinic", "Insurance", "Academy"]
CO_SUFFIX = ["LLC", "Inc", "Group", "Co", ""]


def signup_date():
    if random.random() < 0.28:
        return date(2022, 1, 1) + timedelta(days=random.randint(0, 729))
    # growth: more sign-ups later in the period
    span = (date(2026, 5, 31) - START).days
    return START + timedelta(days=int(span * math.sqrt(random.random())))


customers, used_names = [], set()
for i in range(1, 901):
    segment = weighted(["Consumer", "Small Business", "Corporate"], [50, 32, 18])
    while True:
        if segment == "Consumer":
            name = f"{random.choice(FIRST)} {random.choice(LAST)}"
        else:
            name = " ".join(x for x in (random.choice(CO_ADJ), random.choice(CO_NOUN), random.choice(CO_SUFFIX)) if x)
        if name not in used_names:
            used_names.add(name)
            break
    st = weighted(STATES, [s[3] for s in STATES])
    signup = signup_date()
    churn_after = None
    if random.random() < 0.45:
        churn_after = signup + timedelta(days=int(random.expovariate(1 / 300)))
    customers.append({"customer_id": f"C{i:05d}", "customer_name": name, "segment": segment, "city": random.choice(st[4]),
                      "state": st[0], "signup": signup, "churn_after": churn_after,
                      "activity": random.lognormvariate(0, 1.0) * (2.5 if segment == "Corporate" else 1.0),
                      "rep": random.choice(REPS_BY_REGION[st[2]])[0]})
CUST = {c["customer_id"]: c for c in customers}

# --------------------------------------------------------------------------
# Orders
# --------------------------------------------------------------------------
SEASON = {1: 0.85, 2: 0.85, 3: 0.95, 4: 0.95, 5: 1.0, 6: 0.98, 7: 0.95, 8: 1.08, 9: 1.02, 10: 1.0, 11: 1.25, 12: 1.30}
DOW = [1.05, 1.05, 1.0, 1.0, 0.95, 0.85, 0.75]
CHANNEL_CATEGORY = {
    "Online": {"Furniture": 18, "Office Supplies": 22, "Technology": 38, "Home & Decor": 22},
    "Retail Store": {"Furniture": 20, "Office Supplies": 35, "Technology": 25, "Home & Decor": 20},
    "Wholesale": {"Furniture": 30, "Office Supplies": 45, "Technology": 20, "Home & Decor": 5},
}
PROD_BY_CAT = {}
for p in products:
    PROD_BY_CAT.setdefault(p["category"], []).append(p)


def poisson(lam):
    l, k, p = math.exp(-lam), 0, 1.0
    while True:
        p *= random.random()
        if p <= l:
            return k
        k += 1


def quantity(channel, cat):
    if channel == "Wholesale":
        lo, hi = {"Office Supplies": (10, 80), "Furniture": (2, 20), "Technology": (2, 25), "Home & Decor": (2, 15)}[cat]
        return random.randint(lo, hi)
    q = weighted([1, 2, 3], [70, 20, 10])
    return q * random.randint(1, 5) if cat == "Office Supplies" else q


def discount(channel, d, p, qty):
    sub = p["subcategory"]
    if p["category"] == "Furniture" and sub in ("Tables", "Chairs") and date(2025, 7, 1) <= d <= date(2025, 9, 30) \
            and random.random() < 0.7:
        return Decimal(random.choice(["0.25", "0.30"]))                  # summer clearance
    if channel == "Online":
        if (d.month == 11 and d.day >= 20) or d.month == 12:
            return Decimal(random.choice(["0.15", "0.20"])) if random.random() < 0.6 else Decimal("0")
        return Decimal("0.10") if random.random() < 0.15 else Decimal("0")
    if channel == "Retail Store":
        return Decimal(random.choice(["0.05", "0.10"])) if random.random() < 0.10 else Decimal("0")
    return Decimal("0.15") if qty >= 50 else Decimal("0.10") if qty >= 20 else Decimal("0.05") if qty >= 10 else Decimal("0")


orders, lines = [], []
order_no = 100000
for day in range((END - START).days + 1):
    d = START + timedelta(days=day)
    years = day / 365.25
    lam = 13 * (1.16 ** years) * SEASON[d.month] * DOW[d.weekday()]
    eligible = [c for c in customers if c["signup"] <= d and (c["churn_after"] is None or d <= c["churn_after"])]
    for _ in range(poisson(lam)):
        weekend = d.weekday() >= 5
        channel = weighted(["Online", "Retail Store", "Wholesale"], [65, 35, 0] if weekend else [52, 33, 15])
        if channel == "Wholesale":
            pool = [c for c in eligible if c["segment"] != "Consumer"]
        elif channel == "Retail Store":
            pool = [c for c in eligible if c["segment"] != "Corporate"]
        else:
            pool = eligible
        cust = weighted(pool, [c["activity"] for c in pool])
        order_no += 1
        oid = f"SO-{order_no}"
        if channel == "Retail Store":
            ship = d
        else:
            ship = d + timedelta(days=random.randint(2, 5) if channel == "Online" else random.randint(3, 7))
        if ship > END:
            ship = None
        rep = cust["rep"] if channel == "Wholesale" else ""
        orders.append({"order_id": oid, "order_date": d, "ship_date": ship, "customer_id": cust["customer_id"],
                       "channel": channel, "rep": rep})
        n_lines = weighted([1, 2, 3], [55, 30, 15]) if channel == "Online" else \
            random.randint(1, 4) if channel == "Retail Store" else random.randint(2, 6)
        chosen = set()
        for ln in range(1, n_lines + 1):
            cat = weighted(list(CHANNEL_CATEGORY[channel]), list(CHANNEL_CATEGORY[channel].values()))
            while True:
                p = weighted(PROD_BY_CAT[cat], [x["popularity"] for x in PROD_BY_CAT[cat]])
                if p["product_id"] not in chosen:
                    chosen.add(p["product_id"])
                    break
            qty = quantity(channel, cat)
            disc = discount(channel, d, p, qty)
            gross = money(qty * p["list_price"])
            net = money(qty * p["list_price"] * (1 - disc))
            cost = money(qty * p["unit_cost"])
            lines.append({"order_id": oid, "line": ln, "product_id": p["product_id"], "qty": qty,
                          "unit_price": p["list_price"], "discount": disc, "gross": gross, "net": net, "cost": cost})

ORDER = {o["order_id"]: o for o in orders}

# --------------------------------------------------------------------------
# Returns
# --------------------------------------------------------------------------
REASONS = ["Damaged in transit", "Defective", "Wrong item", "Not as described", "Changed mind"]
returns = []
for ln in lines:
    o, p = ORDER[ln["order_id"]], PROD[ln["product_id"]]
    if o["ship_date"] is None:
        continue
    rate = {"Monitors": 0.09, "Chairs": 0.06}.get(p["subcategory"], 0.035)
    if random.random() >= rate:
        continue
    rdate = o["ship_date"] + timedelta(days=random.randint(3, 30))
    if rdate > END:
        continue
    if p["subcategory"] == "Monitors":
        reason = weighted(REASONS, [55, 25, 8, 7, 5])
    else:
        reason = weighted(REASONS, [15, 15, 20, 20, 30])
    qty_ret = ln["qty"] if ln["qty"] <= 2 else random.randint(1, max(1, ln["qty"] // 3))
    refund = money(ln["net"] * Decimal(qty_ret) / Decimal(ln["qty"]))
    returns.append({"return_id": f"RT-{len(returns) + 1:05d}", "order_id": ln["order_id"], "line": ln["line"],
                    "date": rdate, "qty": qty_ret, "reason": reason, "refund": refund})

# --------------------------------------------------------------------------
# Targets (net sales, by month and region)
# --------------------------------------------------------------------------
actual = {}
for ln in lines:
    o = ORDER[ln["order_id"]]
    key = (o["order_date"].replace(day=1), STATE[CUST[o["customer_id"]]["state"]][2])
    actual[key] = actual.get(key, Decimal(0)) + ln["net"]
targets = []
for (m, region), value in sorted(actual.items()):
    if m.year == 2024:
        t = float(value) * random.gauss(1.02, 0.06)
    else:
        prev = actual.get((m.replace(year=m.year - 1), region), value)
        t = float(prev) * 1.15
    targets.append((m, region, int(round(t, -3))))

# --------------------------------------------------------------------------
# Expected clean output (answer key)
# --------------------------------------------------------------------------
missing_segment = set(random.sample([c["customer_id"] for c in customers], 18))

write_csv(EXP / "dim_customer.csv",
          ["customer_id", "customer_name", "segment", "city", "state_code", "state_name", "region", "signup_date"],
          [[c["customer_id"], c["customer_name"], "Unknown" if c["customer_id"] in missing_segment else c["segment"],
            c["city"], c["state"], STATE[c["state"]][1], STATE[c["state"]][2], c["signup"].isoformat()] for c in customers])
write_csv(EXP / "dim_product.csv",
          ["product_id", "product_name", "category", "subcategory", "unit_cost", "list_price", "is_cost_imputed"],
          [[p["product_id"], p["product_name"], p["category"], p["subcategory"], p["unit_cost"], p["list_price"],
            int(p.get("cost_imputed", False))] for p in products])
write_csv(EXP / "dim_sales_rep.csv", ["sales_rep_id", "sales_rep_name", "region", "hire_date"],
          [[r[0], r[1], r[2], r[3].isoformat()] for r in REPS])
write_csv(EXP / "fact_sales.csv",
          ["order_id", "order_line", "order_date", "ship_date", "customer_id", "product_id", "sales_rep_id", "channel",
           "quantity", "unit_price", "discount_pct", "gross_sales", "discount_amount", "net_sales", "cost", "gross_profit"],
          [[ln["order_id"], ln["line"], ORDER[ln["order_id"]]["order_date"].isoformat(),
            ORDER[ln["order_id"]]["ship_date"].isoformat() if ORDER[ln["order_id"]]["ship_date"] else "",
            ORDER[ln["order_id"]]["customer_id"], ln["product_id"], ORDER[ln["order_id"]]["rep"],
            ORDER[ln["order_id"]]["channel"], ln["qty"], ln["unit_price"], ln["discount"], ln["gross"],
            ln["gross"] - ln["net"], ln["net"], ln["cost"], ln["net"] - ln["cost"]] for ln in lines])
write_csv(EXP / "fact_returns.csv",
          ["return_id", "order_id", "order_line", "return_date", "quantity_returned", "return_reason", "refund_amount"],
          [[r["return_id"], r["order_id"], r["line"], r["date"].isoformat(), r["qty"], r["reason"], r["refund"]] for r in returns])
write_csv(EXP / "fact_sales_target.csv", ["month_start", "region", "target_net_sales"],
          [[m.isoformat(), reg, t] for m, reg, t in targets])

# --------------------------------------------------------------------------
# Raw, messy exports
# --------------------------------------------------------------------------
MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


def messy_date(d, with_time=True):
    r = random.random()
    if r < 0.65:
        return d.isoformat()
    if r < 0.85:
        return d.strftime("%m/%d/%Y")
    if r < 0.95 and with_time:
        return f"{d.isoformat()} {random.randint(8, 20):02d}:{random.randint(0, 59):02d}:{random.randint(0, 59):02d}"
    return f"{MONTHS[d.month - 1]} {d.day:02d}, {d.year}"


def messy_id(x, p=0.08):
    if random.random() >= p:
        return x
    return random.choice([x.lower(), f" {x}", f"{x} ", x.lower() + " "])


CHANNEL_VARIANTS = {"Online": ["Online"] * 6 + ["online", "ONLINE", "Web", "E-commerce"],
                    "Retail Store": ["Retail Store"] * 6 + ["Retail", "Store", "retail store"],
                    "Wholesale": ["Wholesale"] * 6 + ["wholesale", "B2B"]}


def messy_money(v, p_blank=0.0):
    r = random.random()
    if r < p_blank:
        return ""
    if r < p_blank + 0.05:
        return f"${v:,.2f}"
    return f"{v}"


def messy_discount(v):
    r = random.random()
    if v == 0:
        return random.choice(["", "0", "0", "0%"])
    if r < 0.30:
        return f"{int(v * 100)}%"
    return f"{v.normalize()}" if r < 0.9 else f"{v}"


def messy_qty(q):
    r = random.random()
    if r < 0.03:
        return f"{q} units"
    if r < 0.06:
        return f" {q} "
    return str(q)


REP_NAME = {r[0]: r[1] for r in REPS}
raw_lines = []
for ln in lines:
    o = ORDER[ln["order_id"]]
    rep = o["rep"]
    if rep and random.random() < 0.03:
        rep = REP_NAME[rep]                                    # name typed instead of the ID
    raw_lines.append([o["order_id"], messy_date(o["order_date"]),
                      messy_date(o["ship_date"]) if o["ship_date"] else "", messy_id(o["customer_id"]), rep,
                      random.choice(CHANNEL_VARIANTS[o["channel"]]), ln["line"], messy_id(ln["product_id"], 0.05),
                      messy_qty(ln["qty"]), messy_money(ln["unit_price"], p_blank=0.025), messy_discount(ln["discount"])])

# ship date before order date (fields swapped by the operator)
swapped, swapped_rows = 0, set()
for row in random.sample(raw_lines, int(len(raw_lines) * 0.005)):
    o = ORDER[row[0]]
    if o["ship_date"] and o["ship_date"] > o["order_date"]:
        row[1], row[2] = o["ship_date"].isoformat(), o["order_date"].isoformat()
        swapped += 1
        swapped_rows.add(id(row))

extra = []
max_line = {}
for ln in lines:
    max_line[ln["order_id"]] = max(max_line.get(ln["order_id"], 0), ln["line"])


def extra_line(order_id, sku, qty, price):
    o = ORDER[order_id]
    max_line[order_id] += 1
    return [order_id, o["order_date"].isoformat(), o["ship_date"].isoformat() if o["ship_date"] else "",
            o["customer_id"], o["rep"], o["channel"], max_line[order_id], sku, qty, price, "0"]


order_ids = [o["order_id"] for o in orders]
for oid in random.sample(order_ids, int(len(lines) * 0.003)):      # SKU not in the product master
    extra.append(extra_line(oid, random.choice(["TEC-ACC-9999", "FUR-CHA-9998", "OFF-PAP-9997"]), 1, "49.99"))
for oid in random.sample(order_ids, int(len(lines) * 0.005)):      # zero / negative quantity
    p = random.choice(products)
    extra.append(extra_line(oid, p["product_id"], random.choice(["0", "-1", "-2", "-5"]), str(p["list_price"])))
test_orders = 0
for i in range(int(len(lines) * 0.002)):                            # test orders from the web team
    p = random.choice(products)
    d = START + timedelta(days=random.randint(0, (END - START).days))
    extra.append([f"SO-TEST{i + 1:03d}", d.isoformat(), d.isoformat(), "TEST", "", "Online", 1, p["product_id"], "1",
                  str(p["list_price"]), "0"])
    test_orders += 1

dups = [list(r) for r in random.sample(raw_lines, int(len(raw_lines) * 0.02))]    # exact duplicates
reformatted = []
not_swapped = [r for r in raw_lines if id(r) not in swapped_rows]
for r in random.sample(not_swapped, int(len(raw_lines) * 0.01)):                   # same line, different formatting
    o = ORDER[r[0]]
    r2 = list(r)
    r2[1] = o["order_date"].strftime("%m/%d/%Y")
    r2[3] = o["customer_id"].lower()
    reformatted.append(r2)

all_raw = raw_lines + extra + dups + reformatted
random.shuffle(all_raw)
write_csv(RAW / "orders_raw.csv", ["OrderID", "OrderDate", "ShipDate", "CustomerID", "SalesRep", "Channel", "LineNo",
                                   "SKU", "Qty", "UnitPrice", "Discount"], all_raw)

# customers: duplicates with an older version, inconsistent states, missing segments, extra spaces
cust_raw = []
for c in customers:
    st = STATE[c["state"]]
    state_txt = random.choice(st[5]) if random.random() < 0.25 else st[0]
    name = c["customer_name"]
    if random.random() < 0.05:
        name = f"  {name} " if random.random() < 0.5 else name.replace(" ", "  ", 1)
    seg = "" if c["customer_id"] in missing_segment else c["segment"]
    updated = datetime.combine(c["signup"], datetime.min.time()) + timedelta(days=random.randint(0, 200), hours=random.randint(8, 18))
    cust_raw.append([c["customer_id"], name, seg, c["city"], state_txt, messy_date(c["signup"], with_time=False),
                     updated.strftime("%Y-%m-%d %H:%M:%S")])
    if random.random() < 0.03:                                     # older version of the same customer
        other_city = random.choice([s for s in STATES if s[0] != c["state"]])
        older = updated - timedelta(days=random.randint(30, 400))
        cust_raw.append([c["customer_id"], name, seg or "Consumer", random.choice(other_city[4]), other_city[0],
                         c["signup"].isoformat(), older.strftime("%Y-%m-%d %H:%M:%S")])
random.shuffle(cust_raw)
write_csv(RAW / "customers_raw.csv", ["CustomerID", "CustomerName", "Segment", "City", "State", "SignupDate", "UpdatedAt"],
          cust_raw)

CATEGORY_VARIANTS = {"Furniture": ["Furniture", "Furniture", "furniture"],
                     "Office Supplies": ["Office Supplies", "Office Supplies", "Office supplies", "Office-Supplies"],
                     "Technology": ["Technology", "Technology", "Tech", "technology"],
                     "Home & Decor": ["Home & Decor", "Home & Decor", "Home and Decor", "Home&Decor"]}
prod_raw = []
for p in products:
    cost = "" if p["product_id"] in MISSING_COST else str(p["unit_cost"])
    prod_raw.append([p["product_id"], p["product_name"], random.choice(CATEGORY_VARIANTS[p["category"]]), p["subcategory"],
                     cost, f"${p['list_price']}" if random.random() < 0.4 else str(p["list_price"])])
write_csv(RAW / "products_raw.csv", ["SKU", "ProductName", "Category", "SubCategory", "UnitCost", "ListPrice"], prod_raw)

REASON_VARIANTS = {"Damaged in transit": ["Damaged in transit", "damaged", "DAMAGED IN TRANSIT", "Damaged - shipping"],
                   "Defective": ["Defective", "defective item", "Faulty"],
                   "Wrong item": ["Wrong item", "wrong item sent"],
                   "Not as described": ["Not as described", "not as described"],
                   "Changed mind": ["Changed mind", "Customer changed mind", "no longer needed"]}
ret_raw = [[r["return_id"], r["order_id"], r["line"], messy_date(r["date"], with_time=False), r["qty"],
            random.choice(REASON_VARIANTS[r["reason"]])] for r in returns]
n_ret = len(returns)
for i in range(int(n_ret * 0.01)):                                  # unknown order lines
    ret_raw.append([f"RT-{n_ret + i + 1:05d}", f"SO-{random.randint(900000, 999999)}", 1,
                    (START + timedelta(days=random.randint(30, 900))).isoformat(), 1, "Changed mind"])
line_by_key = {(ln["order_id"], ln["line"]): ln for ln in lines}
k = n_ret + int(n_ret * 0.01)
for ln in random.sample(lines, 12):                                 # more returned than sold
    k += 1
    o = ORDER[ln["order_id"]]
    if o["ship_date"] is None:
        continue
    ret_raw.append([f"RT-{k:05d}", ln["order_id"], ln["line"], (o["ship_date"] + timedelta(days=5)).isoformat(),
                    ln["qty"] + random.randint(1, 5), "Defective"])
random.shuffle(ret_raw)
write_csv(RAW / "returns_raw.csv", ["ReturnID", "OrderID", "LineNo", "ReturnDate", "QtyReturned", "Reason"], ret_raw)

write_csv(RAW / "sales_reps.csv", ["SalesRepID", "SalesRepName", "Region", "HireDate"],
          [[r[0], r[1], r[2], r[3].isoformat()] for r in REPS])
write_csv(RAW / "sales_targets.csv", ["Month", "Region", "TargetNetSales"],
          [[m.strftime("%Y-%m"), reg, t] for m, reg, t in targets])

print(f"\ninjected: {len(extra) - test_orders} bad lines, {test_orders} test lines, {len(dups)} exact duplicates, "
      f"{len(reformatted)} reformatted duplicates, {swapped} swapped ship/order dates")
