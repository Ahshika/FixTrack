import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/realtime.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

final usersProvider = FutureProvider<List<AppUser>>((ref) async {
  refreshOn(ref, 'users');
  final api = ref.watch(sessionProvider).value!.api!;
  final res = await api.get('/api/users');
  return (res['users'] as List).map((j) => AppUser.fromJson(j as Map<String, dynamic>)).toList();
});

class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(usersProvider);
    final me = ref.watch(sessionProvider).value!.user!;

    return Scaffold(
      appBar: AppBar(title: const Text('الموظفين')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDialog<void>(context: context, builder: (_) => const UserDialog()),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('موظف جديد'),
      ),
      body: users.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ErrorBanner(errorText(e)),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: () => ref.invalidate(usersProvider), child: const Text('حاول تاني')),
            ]),
          ),
        ),
        data: (list) => RefreshIndicator(
          onRefresh: () => ref.refresh(usersProvider.future),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _UserTile(user: list[i], isMe: list[i].id == me.id),
          ),
        ),
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user, required this.isMe});

  final AppUser user;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final roleColor = switch (user.role) {
      Role.owner => brandOrange,
      Role.reception => brandBlue,
      Role.technician => const Color(0xFF7C3AED),
    };
    return Opacity(
      opacity: user.active ? 1 : 0.55,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: CircleAvatar(
            backgroundColor: roleColor.withValues(alpha: 0.15),
            child: Text(user.name.characters.first, style: TextStyle(color: roleColor).bold),
          ),
          title: Row(
            children: [
              Flexible(child: Text(user.name, style: text.titleSmall?.bold, overflow: TextOverflow.ellipsis)),
              if (isMe) Text('  (إنت)', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
          subtitle: Text('@${user.username}${user.active ? '' : ' • متوقف'}', textDirection: TextDirection.ltr, textAlign: TextAlign.right),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: roleColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
            child: Text(user.role.label, style: TextStyle(color: roleColor).semiBold),
          ),
          onTap: () => showDialog<void>(context: context, builder: (_) => UserDialog(user: user, isMe: isMe)),
        ),
      ),
    );
  }
}

/// إضافة موظف جديد أو تعديل موظف موجود.
class UserDialog extends ConsumerStatefulWidget {
  const UserDialog({super.key, this.user, this.isMe = false});

  final AppUser? user;
  final bool isMe;

  @override
  ConsumerState<UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends ConsumerState<UserDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.user?.name);
  late final _username = TextEditingController(text: widget.user?.username);
  final _password = TextEditingController();
  late Role _role = widget.user?.role ?? Role.technician;
  late bool _active = widget.user?.active ?? true;
  late String _commissionType = widget.user?.commissionType ?? 'none';
  late final _commission = TextEditingController(
    text: widget.user == null || widget.user!.commissionValue == 0
        ? ''
        : widget.user!.commissionType == 'percent'
            ? (widget.user!.commissionValue / 100).toStringAsFixed(widget.user!.commissionValue % 100 == 0 ? 0 : 2)
            : moneyInput(widget.user!.commissionValue),
  );
  bool _busy = false;
  String? _error;

  bool get _isNew => widget.user == null;

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _password.dispose();
    _commission.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = ref.read(sessionProvider).value!.api!;
    try {
      if (_isNew) {
        await api.post('/api/users', {
          'name': _name.text,
          'username': _username.text,
          'password': _password.text,
          'role': _role.name,
        });
      } else {
        await api.patch('/api/users/${widget.user!.id}', {
          'name': _name.text,
          'role': _role.name,
          'active': _active,
          if (_password.text.isNotEmpty) 'password': _password.text,
          'commissionType': _commissionType,
          'commissionValue': _commissionType == 'percent' ? ((double.tryParse(latinDigits(_commission.text)) ?? 0) * 100).round() : (parseMoney(_commission.text) ?? 0),
        });
      }
      ref.invalidate(usersProvider);
      if (!mounted) return;
      Navigator.pop(context);
      showMessage(context, _isNew ? 'تم إضافة ${_name.text}' : 'تم حفظ التعديلات');
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lockSelf = widget.isMe;
    return AlertDialog(
      title: Text(_isNew ? 'موظف جديد' : 'تعديل ${widget.user!.name}'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'الاسم'),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'لازم تكتب الاسم' : null,
                ),
                const SizedBox(height: 12),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: TextFormField(
                    controller: _username,
                    enabled: _isNew,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'اسم المستخدم (بالإنجليزي)'),
                    validator: (v) => RegExp(r'^[a-zA-Z0-9_.]{3,30}$').hasMatch(v?.trim() ?? '')
                        ? null
                        : 'من 3 لـ 30 حرف إنجليزي أو أرقام',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: _isNew ? 'كلمة السر' : 'كلمة سر جديدة (سيبها فاضية لو مش عايز تغيرها)',
                  ),
                  validator: (v) {
                    final value = v ?? '';
                    if (!_isNew && value.isEmpty) return null;
                    return value.length < 6 ? '6 حروف أو أرقام على الأقل' : null;
                  },
                ),
                const SizedBox(height: 16),
                Text('الصلاحية', style: Theme.of(context).textTheme.titleSmall?.bold),
                const SizedBox(height: 8),
                SegmentedButton<Role>(
                  segments: [for (final r in Role.values) ButtonSegment(value: r, label: Text(r.label))],
                  selected: {_role},
                  onSelectionChanged: lockSelf ? null : (s) => setState(() => _role = s.first),
                ),
                const SizedBox(height: 6),
                Text(
                  switch (_role) {
                    Role.owner => 'كل الصلاحيات: التقارير والفلوس والإعدادات والموظفين.',
                    Role.reception => 'استلام وتسليم الأجهزة، وطباعة الوصولات، وتحصيل الفلوس.',
                    Role.technician => 'يشوف الأجهزة اللي عليه بس، ويحدّث حالة الإصلاح.',
                  },
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (!_isNew && _role == Role.technician) ...[
                  const SizedBox(height: 16),
                  Text('عمولة الفني', style: Theme.of(context).textTheme.titleSmall?.bold),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'none', label: Text('من غير')),
                      ButtonSegment(value: 'percent', label: Text('نسبة %')),
                      ButtonSegment(value: 'fixed', label: Text('مبلغ لكل جهاز')),
                    ],
                    selected: {_commissionType},
                    onSelectionChanged: (s) => setState(() => _commissionType = s.first),
                  ),
                  if (_commissionType != 'none') ...[
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _commission,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: _commissionType == 'percent' ? 'النسبة من ربح الصيانة (بعد القطع)' : 'المبلغ لكل جهاز اتسلم',
                        suffixText: _commissionType == 'percent' ? '%' : 'ج.م',
                      ),
                    ),
                  ],
                ],
                if (!_isNew && !lockSelf) ...[
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('الحساب شغال'),
                    subtitle: const Text('لو وقفته، الموظف هيخرج من كل الأجهزة ومش هيقدر يدخل'),
                    value: _active,
                    onChanged: (v) => setState(() => _active = v),
                  ),
                ],
                if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!)],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
        SizedBox(width: 120, child: BusyButton(label: 'حفظ', busy: _busy, onPressed: _save)),
      ],
    );
  }
}
