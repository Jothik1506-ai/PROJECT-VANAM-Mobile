import 'package:flutter/material.dart';

import '../models/family_member.dart';
import '../models/post.dart';
import '../models/web_update.dart';
import '../theme/tokens.dart';
import '../widgets/post_card.dart';
import '../widgets/story_avatar.dart';
import '../widgets/vanam_logo.dart';
import '../widgets/web_update_card.dart';

/// Home feed screen.
/// Web updates are sourced from the current VANAM web hub list. Family posts
/// are still local preview data until the posting backend is connected.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _HomeAppBar(),
            Divider(height: 1, color: palette.line),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(VanamSpacing.md),
                children: [
                  SizedBox(
                    height: 88,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        const AddMemberAvatar(),
                        for (final member in mockFamilyMembers) ...[
                          const SizedBox(width: VanamSpacing.md),
                          StoryAvatar(name: member.name),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: VanamSpacing.lg),
                  const _SectionHeader(
                    title: 'Web Page Updates',
                    subtitle: 'Latest VANAM web pages available for reading.',
                  ),
                  const SizedBox(height: VanamSpacing.md),
                  for (final update in webUpdates)
                    WebUpdateCard(update: update),
                  const SizedBox(height: VanamSpacing.md),
                  const _SectionHeader(
                    title: 'Family Updates',
                    subtitle:
                        'Posts shared by family members will appear here.',
                  ),
                  const SizedBox(height: VanamSpacing.md),
                  if (mockPosts.isEmpty)
                    const _EmptyFamilyUpdates()
                  else
                    for (final post in mockPosts)
                      RepaintBoundary(child: PostCard(post: post)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeAppBar extends StatelessWidget {
  const _HomeAppBar();

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: VanamSpacing.md,
        vertical: VanamSpacing.sm,
      ),
      child: Row(
        children: [
          const VanamLogo(size: 40),
          const SizedBox(width: VanamSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Vanam',
                style: TextStyle(
                  color: palette.ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              Text(
                'Family Hub',
                style: TextStyle(fontSize: 12, color: palette.inkMuted),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            onPressed: () {},
            icon: Icon(Icons.search, color: palette.ink),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                onPressed: () {},
                icon: Icon(
                  Icons.notifications_none_rounded,
                  color: palette.ink,
                ),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: palette.danger,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: palette.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: TextStyle(color: palette.inkMuted, fontSize: 13)),
      ],
    );
  }
}

class _EmptyFamilyUpdates extends StatelessWidget {
  const _EmptyFamilyUpdates();

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return Container(
      padding: const EdgeInsets.all(VanamSpacing.lg),
      decoration: BoxDecoration(
        color: palette.surfaceCard,
        borderRadius: BorderRadius.circular(VanamRadii.card),
        border: Border.all(color: palette.line),
      ),
      child: Row(
        children: [
          Icon(Icons.post_add_rounded, color: palette.brand),
          const SizedBox(width: VanamSpacing.sm),
          Expanded(
            child: Text(
              'No family posts yet. Posting will be connected next.',
              style: TextStyle(color: palette.inkMuted, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}
