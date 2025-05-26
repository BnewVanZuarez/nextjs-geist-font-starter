import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../services/supabase_service.dart';

// Provider for all users
final usersProvider = FutureProvider<List<UserModel>>((ref) async {
  final supabase = ref.watch(supabaseServiceProvider);
  final users = await supabase.getUsers();
  return users.map((user) => UserModel.fromJson(user)).toList();
});

class UserManagementPage extends ConsumerStatefulWidget {
  const UserManagementPage({super.key});

  @override
  ConsumerState<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends ConsumerState<UserManagementPage> {
  String? _searchQuery;
  bool _isLoading = false;

  List<UserModel> _filterUsers(List<UserModel> users) {
    if (_searchQuery == null || _searchQuery!.isEmpty) {
      return users;
    }

    final query = _searchQuery!.toLowerCase();
    return users.where((user) {
      return user.email.toLowerCase().contains(query) ||
          user.fullName.toLowerCase().contains(query) ||
          user.role.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _handleRoleChange(UserModel user, String? newRole) async {
    if (newRole == null || newRole == user.role) return;

    setState(() => _isLoading = true);

    try {
      await ref.read(supabaseServiceProvider).updateUserRole(
        userId: user.id,
        role: newRole,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User role updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
        ref.refresh(usersProvider);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showUserDetails(UserModel user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(user.fullName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const Icon(Icons.email),
              title: const Text('Email'),
              subtitle: Text(user.email),
            ),
            ListTile(
              leading: const Icon(Icons.admin_panel_settings),
              title: const Text('Role'),
              subtitle: DropdownButton<String>(
                value: user.role,
                items: ['admin', 'manajer', 'kasir'].map((role) {
                  return DropdownMenuItem(
                    value: role,
                    child: Text(role[0].toUpperCase() + role.substring(1)),
                  );
                }).toList(),
                onChanged: (newRole) {
                  Navigator.pop(context);
                  _handleRoleChange(user, newRole);
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: const Text('Joined'),
              subtitle: Text(user.createdAt.toString().split('.')[0]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider).value;
    final usersAsync = ref.watch(usersProvider);

    // Only admin can access this page
    if (currentUser == null || !currentUser.isAdmin) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.admin_panel_settings,
                size: 64,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              const Text(
                'Access Denied',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'You need admin privileges to access this page.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('User Management'),
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Search Users',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),

          // Users List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : usersAsync.when(
                    data: (users) {
                      final filteredUsers = _filterUsers(users);
                      return filteredUsers.isEmpty
                          ? const Center(
                              child: Text('No users found'),
                            )
                          : ListView.builder(
                              itemCount: filteredUsers.length,
                              itemBuilder: (context, index) {
                                final user = filteredUsers[index];
                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: user.isAdmin
                                          ? Colors.red
                                          : user.isManager
                                              ? Colors.orange
                                              : Colors.blue,
                                      child: Text(
                                        user.fullName[0].toUpperCase(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    title: Text(user.fullName),
                                    subtitle: Text(user.email),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Chip(
                                          label: Text(
                                            user.role[0].toUpperCase() +
                                                user.role.substring(1),
                                          ),
                                          backgroundColor: user.isAdmin
                                              ? Colors.red[100]
                                              : user.isManager
                                                  ? Colors.orange[100]
                                                  : Colors.blue[100],
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.edit),
                                          onPressed: () => _showUserDetails(user),
                                        ),
                                      ],
                                    ),
                                    onTap: () => _showUserDetails(user),
                                  ),
                                );
                              },
                            );
                    },
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, stack) => Center(
                      child: Text('Error: ${error.toString()}'),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
