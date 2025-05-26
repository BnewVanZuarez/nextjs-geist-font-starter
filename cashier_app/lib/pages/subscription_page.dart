import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/subscription_model.dart';
import '../providers/auth_provider.dart';
import '../services/supabase_service.dart';

// Provider for current user's subscription
final currentSubscriptionProvider = FutureProvider<SubscriptionModel?>((ref) async {
  final user = ref.watch(currentUserProvider).value;
  if (user == null) return null;

  try {
    final supabase = ref.watch(supabaseServiceProvider);
    final subscription = await supabase.getCurrentSubscription(user.id);
    return SubscriptionModel.fromJson(subscription);
  } catch (e) {
    return null;
  }
});

class SubscriptionPage extends ConsumerWidget {
  const SubscriptionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscriptionAsync = ref.watch(currentSubscriptionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscription'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Current Subscription Status
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Column(
                children: [
                  const Text(
                    'Current Subscription',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  subscriptionAsync.when(
                    data: (subscription) => subscription != null
                        ? Column(
                            children: [
                              Text(
                                subscription.package.displayName,
                                style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                subscription.status,
                                style: TextStyle(
                                  fontSize: 18,
                                  color: subscription.isExpired
                                      ? Colors.red
                                      : Colors.green,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Valid until: ${subscription.formattedEndDate}',
                                style: const TextStyle(fontSize: 16),
                              ),
                              Text(
                                '${subscription.daysRemaining} days remaining',
                                style: const TextStyle(fontSize: 16),
                              ),
                            ],
                          )
                        : const Text(
                            'No active subscription',
                            style: TextStyle(fontSize: 18),
                          ),
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, stack) => Text(
                      'Error: ${error.toString()}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),

            // Subscription Packages
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Text(
                    'Choose Your Plan',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 32),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return constraints.maxWidth > 800
                          ? Row(
                              children: [
                                for (final package in SubscriptionPackage.values)
                                  Expanded(
                                    child: _buildPackageCard(
                                      context,
                                      package,
                                      ref,
                                      subscriptionAsync.value?.package == package,
                                    ),
                                  ),
                              ],
                            )
                          : Column(
                              children: [
                                for (final package in SubscriptionPackage.values)
                                  _buildPackageCard(
                                    context,
                                    package,
                                    ref,
                                    subscriptionAsync.value?.package == package,
                                  ),
                              ],
                            );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPackageCard(
    BuildContext context,
    SubscriptionPackage package,
    WidgetRef ref,
    bool isCurrentPlan,
  ) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  package.displayName,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (isCurrentPlan)
                  const Chip(
                    label: Text('Current Plan'),
                    backgroundColor: Colors.green,
                    labelStyle: TextStyle(color: Colors.white),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Rp ${package.monthlyPrice.toStringAsFixed(2)}/month',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
              ),
            ),
            const SizedBox(height: 24),
            ...package.features.map(
              (feature) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(feature)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isCurrentPlan
                    ? null
                    : () => _handleSubscribe(context, ref, package),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor:
                      isCurrentPlan ? Colors.grey : Colors.indigo,
                ),
                child: Text(
                  isCurrentPlan ? 'Current Plan' : 'Subscribe Now',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleSubscribe(
    BuildContext context,
    WidgetRef ref,
    SubscriptionPackage package,
  ) async {
    final user = ref.read(currentUserProvider).value;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please login to subscribe'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Subscribe to ${package.displayName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Price: Rp ${package.monthlyPrice.toStringAsFixed(2)}/month'),
            const SizedBox(height: 16),
            const Text('Features:'),
            ...package.features.map(
              (feature) => Padding(
                padding: const EdgeInsets.only(left: 16, top: 4),
                child: Text('• $feature'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Subscribe'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Create subscription
      final startDate = DateTime.now();
      final endDate = startDate.add(const Duration(days: 30));

      await ref.read(supabaseServiceProvider).createSubscription(
        userId: user.id,
        package: package.name,
        startDate: startDate,
        endDate: endDate,
      );

      ref.refresh(currentSubscriptionProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Subscription successful'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
