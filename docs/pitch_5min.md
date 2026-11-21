# Ahead: the five-minute pitch without slides

For the WHU video interview. About 580 words, roughly four and a half minutes at a calm pace. It follows the deck slide by slide. Say it, do not read it.

**Opening.** Hi, I'm Luis. I built Ahead, a personal finance agent for young employees in Germany who have put off their tax return and their pension for years.

**Opportunity.** Start with one number. In Germany, about fifteen million employees file a tax return. Thirteen million of them get money back, on average 1,240 euros. Another eleven and a half million never file. That is money people are owed and never receive. At the same time, a quarter of Germans have already asked an AI about money. The technology to do this work for people exists, and people are ready for it.

**Problem.** My target group is 25 to 35, a few years into the job. They earn enough to care about security. They know they should file, claim what their employer would add, look at their pension. And they never get to it. It is not a lack of knowledge, and it is not a lack of apps. The bank app shows a balance, ChatGPT explains the pension. Nobody gets the postponed thing done with them.

**Solution.** Ahead answers three questions with your own numbers. Where do I stand? Where do I lose money? What is my next step? And then it acts. It finds an open tax year, tells you roughly what is in it, and asks: shall I prepare it? After your yes it fills it in with you. It asks before every action, and every change can be undone. I built all of it myself, the app, the server and the agent, and it runs today in guest mode on the web.

**Validation.** Before building more, I tested the offer twice with simulated buyers: AI personas, not customers. The first offer was 49 euros a year with a bank file upload. Zero of sixty would pay. So I changed it: a free check without a file, and 29 euros a year only after Ahead has found at least a hundred. I showed that to five groups of twelve. Six of sixty would pay, and five of the six gave the same reason: I have put this off for years. That is how I found my target group. It is not sales data. It told me where the offer breaks and who it is for.

**Business model.** The check is free. Ahead Plus is the doing: Ahead prepares the tax return, the letters and the applications with you. It costs 29 euros a year and is only offered after a find of a hundred euros or more. If less than a hundred comes back in the first year, the fee is refunded. About twenty euros stay per customer. A second payer I want to test is employers, who offer Ahead to their young staff.

**Market.** There are 26.8 million employees in Germany, and 11.6 million of them never file. I start with the 25 to 35-year-olds among them. How many that is, I still have to find out.

**Competition.** Finanzguru shows the overview. Taxfix files tax returns, and only that. ChatGPT gives good answers but does not know your payments. Ahead covers all money topics for one group and takes the next step. I have no lasting advantage yet. I will have to earn it by reaching this group first.

**Next steps.** I am not asking for money, and I have no users yet. In thirty days the new offer is live. In sixty days I have talked to fifteen people from my target group and watched five use it. In ninety days I run a price test with a hundred strangers. If fewer than five pay, I change the model again.

**Why WHU.** I can build. What I want to learn at WHU is how to take a product to its first hundred paying customers, with people who challenge it. Thank you.

## Sources for the numbers

Checked on 21 November 2026.

- 1,240 euros, 15.2 million filed, 13.2 million refunded, 26.8 million employees: Destatis, "Steuererklärung: Durchschnittliche Rückerstattung lag bei 1 240 Euro", 10 June 2026, data for 2022. The 11.6 million who did not file is 26.8 minus 15.2, own calculation.
- 25 percent have asked an AI such as ChatGPT about money, 68 percent of 16 to 29-year-olds see AI in finance as an opportunity: Bitkom, 21 May 2026, 1,004 respondents.
- 95 percent of 17 to 27-year-olds expect security from their retirement provision, 91 percent want plain language: MetallRente youth study 2025, as reported by ihre-vorsorge.de on 12 June 2025.
- Instinct raised 1 billion dollars: TechCrunch, 28 September 2026.
- Taxfix: more than 10 million returns, from 39.99 euros. Finanzguru: 4,000+ banks, paid plan 0.99 euros a week. Both from the companies' own websites, read on 20 November 2026.
- Test 1 (0 of 60) is in `founder/ahead/v9/panel/`, test 2 (6 of 60, five groups of twelve) in `founder/ahead/v9/zielgruppe/`. AI personas, not customers.
- Per customer: 29.00 minus 4.63 VAT, 0.69 payment fee (1.5 percent plus 0.25), 1.80 for 120 AI answers at 1.5 cents, 1.45 for 5 percent refunds, leaves 20.43. All assumptions.
- 29 euros a year and the employer model are planned, not built. The app today shows 4.99 euros a month or 49 euros a year.
- The success thresholds on slide 10 (100 checks, 3 of 5, 5 payers) are targets I set, not benchmarks.
