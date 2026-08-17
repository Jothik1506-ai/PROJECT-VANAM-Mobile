import 'package:flutter/material.dart';

import '../models/family_member.dart';
import '../models/post.dart';
import '../theme/tokens.dart';
import '../widgets/post_card.dart';
import '../widgets/story_avatar.dart';

/// Home feed screen — PREVIEW ONLY.
/// ARCHITECTURE.md Section 9 defers Home Feed to Phase 3. This screen uses
/// mock data and is not wired to any backend or reachable from the real V1
/// app (lib/main.dart). It exists so the planned UI can be reviewed.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _HomeAppBar(),
            const Divider(height: 1, color: VanamColors.line),
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
                  const Text(
                    'Family Updates',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: VanamColors.ink,
                    ),
                  ),
                  const SizedBox(height: VanamSpacing.md),
                  for (final post in mockPosts) PostCard(post: post),
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
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: VanamSpacing.md,
        vertical: VanamSpacing.sm,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: Image.asset(
              'assets/brand/Final.png',
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: VanamSpacing.sm),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Vanam',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
              ),
              Text(
                'Family Hub',
                style: TextStyle(fontSize: 12, color: VanamColors.inkMuted),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.search, color: VanamColors.ink),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                onPressed: () {},
                icon: const Icon(
                  Icons.notifications_none_rounded,
                  color: VanamColors.ink,
                ),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: VanamColors.danger,
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
