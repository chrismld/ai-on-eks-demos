#!/usr/bin/env python3
import argparse
import datetime as dt
import math
import random

def clamp(x, lo, hi):
    return lo if x < lo else hi if x > hi else x

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seconds", type=int, default=3600, help="total duration")
    ap.add_argument("--step", type=int, default=5, help="sampling period in seconds")
    ap.add_argument("--seed", type=int, default=42, help="rng seed (reproducible)")
    ap.add_argument("--base", type=float, default=320.0, help="baseline MiB")
    ap.add_argument("--min", dest="minv", type=float, default=180.0, help="min clamp MiB")
    ap.add_argument("--max", dest="maxv", type=float, default=950.0, help="max clamp MiB")
    ap.add_argument("--small_p", type=float, default=0.10, help="prob of small spike each step")
    ap.add_argument("--big_p", type=float, default=0.012, help="prob of big spike each step")
    args = ap.parse_args()

    random.seed(args.seed)

    n = args.seconds // args.step
    now = dt.datetime.now(dt.timezone.utc)
    # start 1h window ending now, aligned to step
    start_epoch = int(now.timestamp()) - args.seconds
    start_epoch = start_epoch - (start_epoch % args.step)
    start = dt.datetime.fromtimestamp(start_epoch, tz=dt.timezone.utc)

    # Mean-reverting baseline (Ornstein–Uhlenbeck-ish)
    x = args.base
    mu = args.base
    theta = 0.18  # pull-back strength
    sigma = 9.0   # jaggedness

    # Spike buffers with exponential decay
    small_buf = 0.0
    big_buf = 0.0
    small_tau_steps = 6    # ~30s half-ish decay
    big_tau_steps = 18     # ~90s decay
    small_decay = math.exp(-1.0 / small_tau_steps)
    big_decay   = math.exp(-1.0 / big_tau_steps)

    # Extra “micro-spike” noise to look like zoomed-out stock chart
    micro_sigma = 6.5

    print("time,value")
    t = start
    for i in range(n):
        # decay prior spikes
        small_buf *= small_decay
        big_buf *= big_decay

        # random impulses (lots of tiny, few big)
        if random.random() < args.small_p:
            # lognormal-ish small impulses (5–50 MiB typical)
            amp = math.exp(random.gauss(math.log(14), 0.55))
            small_buf += amp

        if random.random() < args.big_p:
            # rarer big impulses (60–350 MiB typical)
            amp = math.exp(random.gauss(math.log(140), 0.55))
            big_buf += amp

        # OU update + jagged noise
        dt_step = 1.0  # treat as unit step
        x += theta * (mu - x) * dt_step + random.gauss(0, sigma)

        # micro jaggedness + a tiny “directional” bias sometimes
        micro = random.gauss(0, micro_sigma)
        if random.random() < 0.06:
            micro += random.choice([-1, 1]) * random.uniform(8, 22)

        y = x + small_buf + big_buf + micro

        # clamp to realistic container range
        y = clamp(y, args.minv, args.maxv)

        print(f"{t.isoformat().replace('+00:00','Z')},{int(round(y))}")
        t += dt.timedelta(seconds=args.step)

if __name__ == "__main__":
    main()

