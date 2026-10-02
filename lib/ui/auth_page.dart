import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/api_client.dart';
import '../data/secure_session.dart';
import '../data/server_config.dart';
import 'theme.dart';

class AuthPage extends StatefulWidget {
  final Future<void> Function(AuthSession session, FlowApi api) onAuthenticated;
  final VoidCallback? onContinueLocal;
  final FlowApi Function(Uri)? apiFactory;
  const AuthPage({
    super.key,
    required this.onAuthenticated,
    this.onContinueLocal,
    this.apiFactory,
  });
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController(),
      _password = TextEditingController(),
      _name = TextEditingController(),
      _code = TextEditingController();
  bool _register = false, _busy = false, _obscure = true;
  bool _sending = false;
  int _retrySeconds = 0;
  Timer? _resendTimer;
  String? _error;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _code.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _busy || _sending) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final server = Uri.parse(flowdayServerUrl);
      final api = widget.apiFactory?.call(server) ?? FlowApi(server);
      final session = _register
          ? await api.register(
              _email.text.trim(),
              _password.text,
              _name.text.trim(),
              verificationCode: _code.text.trim(),
            )
          : await api.login(_email.text.trim(), _password.text);
      await widget.onAuthenticated(session, api);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on SecureSessionException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '登录失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() async {
    if (_sending || _busy || _retrySeconds > 0) return;
    final email = _email.text.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => _error = '请输入有效的邮箱地址');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final server = Uri.parse(flowdayServerUrl);
      final api = widget.apiFactory?.call(server) ?? FlowApi(server);
      await api.sendRegistrationCode(email);
      if (!mounted) return;
      setState(() {
        _retrySeconds = 60;
        _code.clear();
      });
      _resendTimer?.cancel();
      _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() => _retrySeconds--);
        if (_retrySeconds <= 0) timer.cancel();
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '验证码发送失败，请重试');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _verificationField() => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            controller: _code,
            enabled: !_busy && !_sending,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            decoration: const InputDecoration(
              labelText: '邮箱验证码',
              prefixIcon: Icon(Icons.verified_user_outlined, size: 20),
            ),
            validator: (value) =>
                value == null || !RegExp(r'^\d{6}$').hasMatch(value.trim())
                ? '请输入 6 位验证码'
                : null,
            onFieldSubmitted: (_) => _submit(),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 130,
          height: 48,
          child: OutlinedButton(
            onPressed: _busy || _sending || _retrySeconds > 0
                ? null
                : _sendCode,
            child: Text(
              _sending
                  ? '发送中'
                  : _retrySeconds > 0
                  ? '$_retrySeconds 秒后重发'
                  : '发送验证码',
            ),
          ),
        ),
      ],
    ),
  );

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool password = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      enabled: !_busy && !_sending,
      obscureText: password && _obscure,
      keyboardType: controller == _email
          ? TextInputType.emailAddress
          : TextInputType.text,
      autofillHints: controller == _email
          ? const [AutofillHints.email]
          : password
          ? [_register ? AutofillHints.newPassword : AutofillHints.password]
          : const [AutofillHints.name],
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: password
            ? IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              )
            : null,
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) return '请输入$label';
        if (controller == _email &&
            !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())) {
          return '请输入有效的邮箱地址';
        }
        if (password && _register && value.length < 10) return '密码至少需要 10 个字符';
        return null;
      },
      onFieldSubmitted: (_) => _submit(),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Theme.of(context).colorScheme.surface,
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final form = Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 390),
                child: AutofillGroup(
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _busy || _sending
                                ? null
                                : () => setState(() {
                                    _register = !_register;
                                    _error = null;
                                    _code.clear();
                                  }),
                            child: Text(_register ? '已有账号？立即登录' : '没有账号？立即注册'),
                          ),
                        ),
                        const SizedBox(height: 40),
                        Text(
                          _register ? '创建账号' : '欢迎回来',
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 28),
                        if (_register)
                          _field(_name, '昵称', Icons.person_outline),
                        _field(_email, '邮箱地址', Icons.mail_outline),
                        _field(
                          _password,
                          '密码',
                          Icons.lock_outline,
                          password: true,
                        ),
                        if (_register) _verificationField(),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        FilledButton(
                          onPressed: _busy || _sending ? null : _submit,
                          child: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(_register ? '注册' : '登录'),
                        ),
                        const SizedBox(height: 16),
                        if (widget.onContinueLocal != null)
                          TextButton(
                            onPressed: _busy ? null : widget.onContinueLocal,
                            child: const Text('继续本地使用'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          if (constraints.maxWidth < 800) return form;
          return Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(56),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xffe5f2ff),
                        Color(0xfff6f9fe),
                        Color(0xffdce9fa),
                      ],
                    ),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 24),
                      Row(
                        children: [
                          Icon(
                            Icons.spa_rounded,
                            color: Color(0xff16c4b7),
                            size: 40,
                          ),
                          SizedBox(width: 12),
                          Text(
                            'FlowDay',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: ink,
                            ),
                          ),
                        ],
                      ),
                      Spacer(),
                      Text(
                        '让时间更有秩序\n让生活更有意义',
                        style: TextStyle(
                          fontSize: 36,
                          height: 1.4,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                      SizedBox(height: 24),
                      Text(
                        '日程、任务、项目、灵感，\n在一个地方，清晰掌控每一天。',
                        style: TextStyle(
                          fontSize: 18,
                          height: 1.7,
                          color: muted,
                        ),
                      ),
                      Spacer(flex: 2),
                    ],
                  ),
                ),
              ),
              Expanded(child: form),
            ],
          );
        },
      ),
    ),
  );
}
