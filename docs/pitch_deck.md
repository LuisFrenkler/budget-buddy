# Ahead — Pitch Deck (WHU Master in Entrepreneurship)

**Format:** 10 slides · **Language:** English (WHU accepts EN/DE; MiE materials typically EN)  
**Audience:** WHU MiE admissions / entrepreneurship review  
**Aligned with:** [WHU recommended structure](https://www.whu.edu/en/programs/master-of-science-programs/master-in-entrepreneurship/application-admissions) + Guy Kawasaki 10 slides · **Competition slide** follows [Max Eckel / WHU](https://kellogg.whu.edu/de/news-insights/whu-magazin/artikel/competition-slide-pitch-deck-mistakes/) (assumption → why it matters → opening; trajectory, not present)

**Presentable HTML:** [pitch_deck.html](pitch_deck.html)  
**PDF for WHU upload:** [Luis_Frenkler_PitchDeck.pdf](Luis_Frenkler_PitchDeck.pdf)  
**Full investor brief:** [business_case.md](business_case.md)

**Regenerate PDF:** open `pitch_deck.html` in Chrome → Print → Save as PDF → Landscape → Margins: None → Background graphics: On.

---

## Slide 1 — Title & Overview

**Ahead**  
*Your buddy for money and the future.*

The money **decision layer** for young adults in Germany.  
Buddy — an AI coach that answers with *your* numbers, before you spend.

| | |
|---|---|
| Stage | Pre-seed / soft launch |
| Product | Built end-to-end (Flutter + backend + Buddy agent) |
| Model | Freemium → Ahead Plus €4.99/mo or €39.99/yr |
| Ask (optional for investors) | €150–250k · 12–18 months runway |

One-liner: *ChatGPT does not know your numbers. Buddy does.*

---

## Slide 2 — Opportunity (Why now)

Three forces meet in Germany:

1. **Gen Z is app-native.** ~95% of 16–29s use online banking (Bitkom). 82% of Gen Z use the banking app to stay in control (ING/Visa) — yet only ~8% use multibanking apps.
2. **AI raised the bar for answers** — but generic chat has no budgets, subscriptions, or real cash flow.
3. **Subscription leakage + life-stage shocks** (first salary, moving, flatshare) create repeated decision moments that dashboards do not close.

**Opening:** Own the *decision moment* on top of the bank the user already opens daily — do not fight to become their twelfth finance dashboard.

---

## Slide 3 — Problem

Young adults already *see* money. They still **guess** when it matters.

| Today | Gap |
|---|---|
| Banking / multibanking apps | Answer “What do I have?” |
| ChatGPT & co. | Talk well, without the user’s real numbers |
| Life moments (trip, move, job) | High stakes, little trusted, affordable coaching |

**Consequence:** Overspend, forgotten subscriptions, delayed buffers — not from lack of data, but from lack of a clear next step grounded in *their* ledger.

---

## Slide 4 — Solution

**Buddy:** a chat-first money coach that calculates with the user’s spending, budgets, contracts, and goals.

**Wedge:** *Ask Buddy before you spend.*  
(“Can I afford an €800 trip?” → answer from remaining budget + subscriptions + goals.)

Also in the loop: natural-language entry, receipt scan, subscription detection with price-rise signals, what-if month simulator, next-step actions (not only text).

**Deliberately secondary:** bank link & portfolio = *context for Buddy*, not the hero. Avoids a feature race against multibanking incumbents.

Never regulated investment advice — orientation and calculation only.

---

## Slide 5 — Business Model & Financials

| | Free | Ahead Plus |
|---|---|---|
| Price | €0 | **€4.99 / month** or **€39.99 / year** (~€3.33/mo) |
| Trial | — | 7 days |
| Cloud Buddy | 5 questions / month | Unlimited |
| Receipts / goals | Limited | Unlimited |
| Offline Buddy, budgets, subscriptions | Included | Included |

**Unit economics (modeled targets, labeled as assumptions)**

| Metric | Target |
|---|---|
| Blended ARPU (paying) | ~€4.20 / month |
| Gross margin | 70–85% after LLM + bank API + store fees |
| CAC (organic + creators, early) | €8–20 |
| Payback | < 4 months if ≥10% of active askers convert |
| North stars | Weekly Buddy asks · affordability-ask share · Free→Plus · D30 retention |

Phase 2+ (not core of this deck): trust-compatible B2B2C (campus / employers) — after consumer habit is proven.

---

## Slide 6 — Market

| Layer | Definition | Order of magnitude |
|---|---|---|
| **TAM** | Online-banking users in DE (Bitkom ~86%; industry often cites ~47M addressable online-banking users) | Large — not our focus |
| **SAM** | Ages 18–34 in DE who actively want to steer spending (~2.5–4M “money-interested”) | Core addressable |
| **SOM (36 mo)** | 0.5–1.5% of SAM registered ≈ **15–40k**; 8–15% of those on Plus | Early scale |

Proof the category works at mass scale in DE: incumbents like Finanzguru report ~1.5M users — while remaining **tracking / contracts-first**, not decision-coach-first.

---

## Slide 7 — Competition *(WHU / Max Eckel lens)*

> Do not claim “we do more.” Make competitor **trade-offs understandable**, then state the **assumption we disagree with**, why it matters, and the **opening**. Position against **trajectory**, not today’s feature list.

### Their choices (rational)

| Player | Sensible trade-off | What that optimizes |
|---|---|---|
| **Finanzguru** | Breadth of banks + contracts as core loop | Habit via aggregation; monetize Plus around overview & contracts |
| **Finanzfluss Copilot** | Content brand + wealth / portfolio | Trust via education; monetize investors & net-worth tracking |
| **Bank apps** | Daily payments & balance | Own the login; keep customer inside the bank |
| **Generic LLMs** | Universal conversation | Distribution; no personal ledger |

They are not “missing AI.” They will add assistants. That is the trajectory.

### Assumption we disagree with

**Incumbent assumption:** *If young adults see their money clearly enough, good decisions follow.*  
**Our assumption:** *Overview is already mostly solved by the bank app. The scarce product is a trustworthy decision in the moment — with the user’s real numbers.*

### Why that is hard for them to “just fix”

- Product identity, UX, and growth loops are built around **aggregation and dashboards**. Bolting chat onto “show everything” still trains users to *look*, not to *decide before spending*.
- Moving the hero to “Ask before you book” **competes with their own core narrative** and with existing Plus packaging.
- Winning our wedge does not require winning the bank-count race — the race they are structured to keep fighting.

### Our opening

Start as the **decision layer on top of the bank people already use** — affordability, subscription pressure, month scenarios — for 18–30 in Germany. Compete on **decision quality and life-stage playbooks**, not on “full-stack multibanking.”

---

## Slide 8 — Go-to-Market

**ICP:** 18–30 in DE, first salary or job change, already uses a banking app, does not keep a strict household book, asks concrete questions (trip, gadgets, flatshare).

**Motion**

1. Soft launch (TestFlight / Play Internal) + creator promo codes  
2. Short “Buddy calculates live” clips (Reels / TikTok / Shorts) — one question, one number, one CTA  
3. Campus & flatshare networks (splits as a viral loop)  
4. ASO: Buddy-first screenshots; subtitle *KI-Coach für dein Alltagsgeld*  
5. Bank link: demo / waitlist until demand; commercial PSD2 when conversion proves the coach

---

## Slide 9 — Team

**Luis Frenkler** — Solo founder  
Built Ahead end to end: Flutter client, Dart backend, encrypted vault, bank sync path, Buddy agent, Plus gating, soft-launch path.

**Why this matters for WHU:** the idea is not slideware — there is a working product and a clear wedge. Capital and program support primarily accelerate **distribution, trust/legal, and life-stage playbooks**, not a rewrite.

---

## Slide 10 — Next Steps / Planning

**Now → 3 months**  
Public soft launch under Ahead · first 1,000 registered · instrument Buddy asks as north star · finish store / legal ops  

**3 → 9 months**  
~10k registered · ≥8% of active askers into Plus trial · creator pipeline · deepen life-stage playbooks (move, first job, flatshare)  

**9 → 18 months**  
~25–40k registered · credible unit economics · Seed-ready retention story  

**Use of a €150–250k pre-seed (if raised):** ~40% GTM/creators · ~20% trust/legal · ~20% infra/bank · ~20% product on the wedge  

**Closing line:** Ahead does not win by doing more finance features. Ahead wins by seeing that **decisions**, not dashboards, are the product.

---

## Speaker notes (5-minute verbal pitch without slides)

WHU MiE interviews often require pitching **without slides**. Suggested arc (~5 min):

1. Hook (20s): “Most money apps show what you have. Ahead answers what to do next — with your numbers.”  
2. Problem (60s): Bank apps + ChatGPT gap; Gen Z already has overview.  
3. Solution + demo story (90s): “Can I afford €800 holiday?” → Buddy; wedge.  
4. Why not Finanzguru (60s): their trade-off is rational; assumption we disagree with; trajectory.  
5. Model + ask/status (60s): Plus pricing; product built; next milestones.  
6. Close (20s): Decision layer, not another multibanking app.

---

## Design checklist (WHU / Eckel)

- [x] Exactly **10 slides**  
- [x] Covers Title, Opportunity, Problem, Solution, Business Model & Financials, Market, Competition, GTM, Team, Next Steps  
- [x] Competition slide avoids “logo 2×2 / we are full-stack / they only do one thing”  
- [x] Competition states **assumption → why it matters → opening** and competitor **trade-offs**  
- [x] Numbers labeled as models/targets where not proven traction  
- [x] Honest stage (product built, external traction early)
