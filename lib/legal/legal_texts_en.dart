// English versions of the legal pages. A convenience translation: the German
// text is binding, and both should be reviewed by a lawyer before release.
import 'legal_info.dart';
import 'legal_texts.dart';

class LegalTextsEn {
  static const _binding = LegalSection('Note',
      'This is a translation for your convenience. Only the German version is legally binding.');

  static String get _contact => '${LegalInfo.provider}\n${LegalInfo.street}\n${LegalInfo.city}\nGermany\n'
      'Email: ${LegalInfo.email}${LegalInfo.phone.isEmpty ? '' : '\nPhone: ${LegalInfo.phone}'}';

  static LegalDoc get imprint => LegalDoc('Legal notice', [
        _binding,
        LegalSection('Information pursuant to § 5 DDG', _contact),
        if (LegalInfo.representative.isNotEmpty) LegalSection('Represented by', LegalInfo.representative),
        if (LegalInfo.register.isNotEmpty) LegalSection('Register entry', LegalInfo.register),
        if (LegalInfo.vatId.isNotEmpty)
          LegalSection('VAT ID', 'VAT identification number pursuant to § 27a UStG: ${LegalInfo.vatId}'),
        LegalSection('Responsible for content pursuant to § 18 (2) MStV',
            '${LegalInfo.responsible}\n${LegalInfo.street}\n${LegalInfo.city}\nGermany'),
        const LegalSection(
            'Consumer dispute resolution',
            'We are neither willing nor obliged to take part in dispute resolution proceedings before a '
                'consumer arbitration board. If you have questions or problems, just write to us and we will '
                'find a solution.'),
        const LegalSection(
            'Liability for content',
            'We create the content of this app with great care. However, we cannot guarantee that market '
                'prices, automatically detected contracts and answers from Buddy are correct, complete and up to '
                'date. They do not replace advice.'),
      ]);

  static LegalDoc get privacy => LegalDoc('Privacy policy', [
        _binding,
        LegalSection(
            'At a glance',
            'Ahead is built so that only you can read your financial data. Transactions, budgets, portfolio '
                'and savings goals are stored on your device. With an account we also keep a copy that is '
                'encrypted on your device with your password before upload: we cannot read it. Other data only '
                'leaves your device when you use a feature that needs it, such as the bank connection or Buddy. '
                'We show no ads, use no tracking and sell no data.\n\n'
                'As of: ${LegalInfo.updated}'),
        LegalSection('1. Controller', _contact),
        const LegalSection(
            '2. Data on your device',
            'The app stores your transactions, budgets, portfolio positions, savings goals, contracts and '
                'settings in your device\'s protected storage. We have no access to it. Only you create exports '
                'and backups. Deleting the app or using "Reset app" removes this data.'),
        const LegalSection(
            '3. User account',
            'For an account we process your name, email address and password. We store the password only as '
                'a secure hash (bcrypt) and sign-in sessions only as a checksum. If you turn on two-factor '
                'authentication, we also store its key so the sign-in code can be checked. It protects sign-in, '
                'not the transactions on your device. The legal basis is Art. 6 (1) (b) GDPR (contract). The '
                'data is deleted as soon as you delete your account.\n\n'
                'So your data is on every device after signing in, we store a copy of your transactions, budgets, '
                'goals, shared expenses, portfolio positions and the bank and portfolio connection. The app '
                'encrypts it before upload (AES-256) with a key derived from your password that never leaves your '
                'device. We only store the encrypted text and cannot open it. That is also why nobody can restore '
                'the copy if you forget your password. The copy is deleted together with the account.'),
        const LegalSection(
            '4. Bank and portfolio connection',
            'When you connect your current account, access runs through Enable Banking Oy (Otaniemi, Finland), '
                'an account information service licensed under the Payment Services Directive (PSD2). You confirm '
                'access directly with your bank; neither we nor the app see your login details. Balance and '
                'transactions are transferred to show them in the app. The consent lasts at most 180 days and can '
                'be ended at any time in the app or at your bank. The legal basis is Art. 6 (1) (b) GDPR.\n\n'
                'When you connect your portfolio, access runs through Parqet (Parqet Fintech GmbH, Germany), where '
                'you connected your portfolio yourself. You allow access directly at Parqet; neither we nor the app '
                'see your login details at Parqet or your broker. Positions, quantities, purchase prices and '
                'current prices are transferred, read-only. You can end the access at any time in the app or at '
                'Parqet under Integrations. The legal basis is Art. 6 (1) (b) GDPR.'),
        const LegalSection(
            '5. Buddy (AI assistant) and receipt scanning',
            'When you ask Buddy a question or scan a receipt, we send your question or the photo and a '
                'summarised overview of your finances (totals, recent bookings, budgets, goals, contracts, '
                'portfolio, wealth, retirement, splits, Plus status; no account numbers or payment details) to '
                'Anthropic, PBC (San Francisco, USA), which runs the AI model Claude. Anthropic processes the data '
                'on our behalf to create the answer and, by contract, does not use it for training. The transfer to '
                'the USA is based on the EU-US Data Privacy Framework or standard contractual clauses (Art. 45, 46 '
                'GDPR). The legal basis is Art. 6 (1) (b) GDPR. Buddy answers simple questions directly on your '
                'device without any transfer. If Google\'s Gemini model is set up instead of Claude, the same data '
                'goes to Google; on the free Gemini tier Google may use it to improve its services. Buddy tells you '
                'before your first question which provider answers. What you explicitly allow Buddy to remember '
                '(for example your life stage or a savings goal) is stored as part of your data and sent along '
                'with the overview. You can see and delete it at any time under "What Buddy knows". Buddy does not '
                'remember health, faith, politics or login details.\n\n'
                'Buddy calculates with tools that run on your device. Only the results it needs for your question '
                '(for example your spending of one month by category) go to the AI provider, not all bookings. If '
                'you rate an answer with thumbs up or down, we store your question, Buddy\'s answer and your reason '
                'without your name, to improve Buddy (Art. 6 (1) (f) GDPR). We do not use conversations to train '
                'AI models.\n\n'
                'Without an account you can ask Buddy general questions. Then only your question and the chat so '
                'far go to the AI provider, no financial data. To limit this to a few questions a day we use a '
                'random device ID and your IP address; we keep both only for the current day in memory. The legal '
                'basis is Art. 6 (1) (f) GDPR (legitimate interest in preventing abuse). The chat itself stays on '
                'your device.\n\n'
                'If you speak to Buddy instead of typing, your device\'s or browser\'s speech recognition turns your '
                'voice into text; depending on the system this happens at the manufacturer (for example Apple or '
                'Google). We only receive the text you then send.'),
        const LegalSection(
            '5a. Waitlist and invitations',
            'If you join the waitlist on the website, we store your email address, the time and, if you came '
                'through an invite link, the code of the person who invited you. We use this only to show you '
                'your place and to tell you about the launch. If you invite someone, we only see that someone '
                'joined with your code; no names or data are exchanged. The legal basis is Art. 6 (1) (b) GDPR. '
                'A short email to us is enough to delete the entry.'),
        const LegalSection(
            '6. Prices and market data',
            'For current prices the app requests public market data: stocks and ETFs through our server from '
                'Yahoo Finance, cryptocurrencies directly from CoinGecko. Only ticker symbols are sent, no details '
                'about your portfolio. With the direct request CoinGecko technically receives your IP address. The '
                'legal basis is Art. 6 (1) (f) GDPR (legitimate interest in current prices).'),
        const LegalSection(
            '7. Ahead Plus and payments',
            'You buy Plus through Apple\'s App Store, Google Play or on the web through Stripe (Stripe Payments '
                'Europe Ltd., Dublin, Ireland). You enter payment details directly on the provider\'s payment page; '
                'the provider processes them under its own responsibility. We only receive whether and which '
                'subscription is active, until when it runs and a shortened payment method (e.g. "Visa •••• 4242") '
                'so you can see it in the app. The legal basis is Art. 6 (1) (b) GDPR; statutory retention '
                'obligations for tax purposes (up to ten years) remain unaffected.'),
        const LegalSection(
            '8. Notifications',
            'The app schedules reminders and notices on your device. There is no push server for these local '
                'notifications. WhatsApp is a separate channel and stays off until you agree in Notifications: then '
                'the server stores only a hash of your number, and Meta (WhatsApp Cloud API) may deliver the weekly '
                'report, budget warning and split reminder. No spam. You can withdraw consent there at any time or '
                'by sending "Stop" in WhatsApp. The legal basis is Art. 6 (1) (a) GDPR. You can also turn off '
                'notifications in your profile or in the system settings.'),
        const LegalSection(
            '9. Server and security',
            'When our server is accessed, technically necessary data such as IP address and time are briefly '
                'processed to establish the connection and prevent abuse (Art. 6 (1) (f) GDPR). The transfer is '
                'encrypted. Secret keys are only on the server, never in the app.'),
        LegalSection(
            '10. Your rights',
            'You have the right of access (Art. 15 GDPR), rectification (Art. 16), erasure (Art. 17), restriction '
                'of processing (Art. 18), data portability (Art. 20) and objection (Art. 21). You can withdraw '
                'consent at any time. Much of this works directly in the app: export data, change or delete your '
                'account, disconnect the bank. For everything else write to ${LegalInfo.email}.\n\n'
                'You can also complain to a data protection supervisory authority, for example '
                '${LegalInfo.authority}.'),
      ]);

  static LegalDoc get terms => LegalDoc('Terms of use', [
        _binding,
        LegalSection(
            '1. Scope',
            'These terms apply to the use of the Ahead app, offered by ${LegalInfo.provider}. '
                'As of: ${LegalInfo.updated}.'),
        const LegalSection(
            '2. What Ahead is',
            'Ahead helps you keep track of income, spending, budgets, contracts, savings goals, your portfolio '
                'and a rough orientation on retirement (pension gap). Ahead is not a bank, makes no payments and '
                'offers no investment, tax, pension or legal advice. Retirement figures are estimates; what counts '
                'is the information from the Deutsche Rentenversicherung and your contract partners. Buddy\'s '
                'answers are generated by an AI and may contain errors; please don\'t make important decisions '
                'based on them alone.'),
        const LegalSection(
            '3. Account',
            'You can try Buddy with general questions without an account. For everything else you need an '
                'account. Keep your password secret and let us know if you suspect misuse. You can delete your '
                'account in the app at any time.'),
        const LegalSection(
            '4. Ahead Plus',
            'The basic features are free. Plus extends the app for a fee of currently €4.99 a month or €39.99 '
                'a year, VAT included. New subscribers can try Plus free for 7 days; if you cancel during the '
                'trial, there are no costs.\n\n'
                'The subscription renews automatically for the chosen term unless you cancel beforehand. You can '
                'cancel at any time to the end of the current term, in the app under Profile › My subscription '
                'or, for purchases in the App Store or Google Play, in their account settings. The terms of the '
                'respective store apply in addition.\n\n'
                'We will tell you about price changes in good time; they only apply from the next term.'),
        const LegalSection(
            '5. Availability',
            'We aim for smooth operation. Bank connection, market data and Buddy also depend on third-party '
                'services and may be temporarily unavailable.'),
        const LegalSection(
            '6. Liability',
            'We are liable without limitation for intent and gross negligence, for injury to life, body or '
                'health and under the Product Liability Act. For slightly negligent breach of essential '
                'contractual obligations, liability is limited to the foreseeable, typically occurring damage. '
                'Otherwise liability for slight negligence is excluded.'),
        const LegalSection(
            '7. Changes',
            'We may adjust these terms if there is an objective reason, such as new features or changed laws. '
                'We will inform you about material changes in the app beforehand.'),
        const LegalSection(
            '8. Final provisions',
            'German law applies. Mandatory consumer protection rules of your country of residence remain '
                'unaffected.'),
      ]);

  static LegalDoc get withdrawal => LegalDoc('Cancellation policy', [
        _binding,
        const LegalSection(
            'Right of withdrawal',
            'You have the right to withdraw from this contract within fourteen days without giving any reason. '
                'The withdrawal period is fourteen days from the day the contract was concluded.'),
        LegalSection(
            'How to withdraw',
            'To exercise your right of withdrawal, you must inform us (${LegalInfo.provider}, ${LegalInfo.street}, '
                '${LegalInfo.city}, email: ${LegalInfo.email}) of your decision to withdraw from this contract by '
                'a clear statement. The easiest way is in the app under Profile › My subscription › "Withdraw from '
                'contract". You can also use the model withdrawal form below, but you don\'t have to.\n\n'
                'To meet the withdrawal deadline, it is enough to send your notice before the withdrawal period '
                'ends. For purchases through the App Store or Google Play, the refund is made by the respective '
                'store.'),
        const LegalSection(
            'Effects of withdrawal',
            'If you withdraw from this contract, we will refund all payments we have received from you without '
                'undue delay and at the latest within fourteen days from the day we received your notice of '
                'withdrawal. We will use the same means of payment you used for the original transaction, unless '
                'expressly agreed otherwise; in no case will you be charged fees for this refund.\n\n'
                'If you requested that the service begin during the withdrawal period, you must pay us a '
                'reasonable amount corresponding to the share of services already provided until the withdrawal, '
                'compared to the full scope of the services under the contract. There are no costs for this during '
                'the free trial.'),
        LegalSection(
            'Model withdrawal form',
            'If you want to withdraw from the contract, please fill in this form and send it back.\n\n'
                'To: ${LegalInfo.provider}, ${LegalInfo.street}, ${LegalInfo.city}, ${LegalInfo.email}\n\n'
                'I/We (*) hereby withdraw from the contract concluded by me/us (*) for the provision of the '
                'following service: Ahead Plus\n\n'
                'Ordered on (*) / received on (*)\n'
                'Name of consumer(s)\n'
                'Address of consumer(s)\n'
                'Signature of consumer(s) (only for notice on paper)\n'
                'Date\n\n'
                '(*) Delete as applicable.'),
      ]);

  static const notes = LegalDoc('Important notes', [
    LegalSection(
        'No investment advice',
        'Portfolio values, price charts and analyses are only for your overview. They are not a recommendation '
            'to buy or sell securities or cryptocurrencies. Investments involve risks, up to total loss.'),
    LegalSection(
        'Market data',
        'Prices may be delayed, incomplete or wrong and are shown without guarantee. The information from your '
            'bank or broker is what counts.'),
    LegalSection(
        'Buddy is an AI',
        'Buddy calculates with your data and writes answers with the help of an AI model. That is handy, but '
            'not infallible. Check numbers before you make important decisions. For tax or legal questions, '
            'talk to a professional.'),
    LegalSection(
        'Retirement and pension gap',
        'The retirement view is a rough orientation: assumptions on withdrawals, returns and the state pension '
            'are simplified. It does not replace pension advice or information from the Deutsche '
            'Rentenversicherung or your contract partners. Taxes and inflation are not included.'),
    LegalSection(
        'Automatic detection',
        'Ahead detects contracts, categories and notices automatically from your transactions. That works most '
            'of the time, but not always. You can correct everything yourself at any time.'),
    LegalSection(
        'Security',
        'Protect your device with a lock and turn on the app lock in your profile. We will never ask for your '
            'bank login details, neither by email nor in the app.'),
  ]);
}
