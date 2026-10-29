"""Tráfico continuo hacia storefront con región y método variados."""

import os
import random
import time
from concurrent.futures import ThreadPoolExecutor

import requests

BASE = os.environ.get("STOREFRONT_URL", "http://storefront:8080")
RPS = float(os.environ.get("RPS", "6"))
COHORTS = [("region-a", "card"), ("region-a", "wallet"),
           ("region-b", "card"), ("region-b", "wallet")]
PRODUCTS = ["sku-coffee", "sku-mug", "sku-beans", "sku-grinder"]


def buy():
    region, method = random.choice(COHORTS)
    body = {"region": region, "method": method,
            "items": random.sample(PRODUCTS, k=random.randint(1, 3))}
    try:
        requests.get(f"{BASE}/api/products", timeout=10)
        requests.post(f"{BASE}/api/checkout", json=body, timeout=15)
    except requests.RequestException as error:
        print(f"loadgen: {error}", flush=True)


def main():
    print(f"loadgen: {RPS} rps hacia {BASE}", flush=True)
    with ThreadPoolExecutor(max_workers=32) as pool:
        while True:
            pool.submit(buy)
            time.sleep(random.expovariate(RPS))


if __name__ == "__main__":
    main()
