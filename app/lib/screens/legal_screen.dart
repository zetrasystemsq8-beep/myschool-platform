import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../widgets/app_card.dart';
import '../widgets/feedback.dart';
import '../widgets/help.dart';

/// Plain-language privacy and terms summary, and how to ask for data to be deleted.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Widget section(String title, List<String> lines) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              for (final l in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('•  ', style: TextStyle(color: cs.primary, fontWeight: FontWeight.bold)),
                    Expanded(child: Text(l, style: theme.textTheme.bodyMedium)),
                  ]),
                ),
            ]),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy and terms')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const HintBanner(
            icon: Icons.privacy_tip_outlined,
            text: 'This is a short summary. The full privacy policy and terms are on the web (links below).',
          ),
          const SizedBox(height: 12),
          section('What your school keeps in MySchool', [
            'Names, admission numbers, classes, results, attendance and the fees your school records.',
            'Messages between parents and teachers, notices, meetings, and notifications.',
            'For sign-in: your email (staff and parents) or admission number and PIN (students).',
          ]),
          section('What MySchool does not do', [
            'No adverts, no selling of data, no tracking of your location, contacts or other apps.',
            'No card or bank details are collected. Fees are only recorded by your school.',
          ]),
          section('Who can see what', [
            'Each school\'s data is kept apart from every other school.',
            'Students and parents see only their own information. Teachers see only the classes they teach.',
            'Private messages are not readable by the school unless someone reports a message.',
          ]),
          section('Your rights', [
            'You can ask your school to show you, correct or delete your information.',
            'Your school decides how long records are kept, within the law.',
          ]),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Delete my data', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Ask your school\'s administrator to delete your account and records, or write to us and we will pass the request to your school. '
                  'Please include your name, your school and your admission number or email.'),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(const ClipboardData(text: AppConfig.supportEmail));
                  if (context.mounted) notify(context, 'Email address copied.');
                },
                icon: const Icon(Icons.copy, size: 18),
                label: const Text(AppConfig.supportEmail),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Full documents', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Tap to copy the link, then open it in your browser.'),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                OutlinedButton(
                  onPressed: () async {
                    await Clipboard.setData(const ClipboardData(text: AppConfig.policyUrl));
                    if (context.mounted) notify(context, 'Privacy policy link copied.');
                  },
                  child: const Text('Privacy policy'),
                ),
                OutlinedButton(
                  onPressed: () async {
                    await Clipboard.setData(const ClipboardData(text: AppConfig.termsUrl));
                    if (context.mounted) notify(context, 'Terms link copied.');
                  },
                  child: const Text('Terms of use'),
                ),
              ]),
            ]),
          ),
        ],
      ),
    );
  }
}
