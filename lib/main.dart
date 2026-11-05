import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

const String kTestAdUnitId = 'ca-app-pub-3940256099942544/5224354917';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'AIzaSyDgexV6CuQmGSowZxh_nVX8-kqhs5BuDw8',
      appId: '1:119761173572:android:f91281da425fd8e8d6d011',
      messagingSenderId: '119761173572',
      projectId: 'reward-app-408a6',
      storageBucket: 'reward-app-408a6.firebasestorage.app',
    ),
  );
  await MobileAds.instance.initialize();
  runApp(const RewardApp());
}

class RewardApp extends StatelessWidget {
  const RewardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Reward App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasData) return const HomePage();
        return const AuthPage();
      },
    );
  }
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _isLogin = true;
  String _msg = '';

  Future<void> _submit() async {
    try {
      if (_isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: _email.text.trim(), password: _pass.text);
      } else {
        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: _email.text.trim(), password: _pass.text);
        await FirebaseFirestore.instance.collection('users').doc(cred.user!.uid).set({
          'points': 0,
          'lastAdAt': null,
          'adCountToday': 0,
          'dayKey': '',
        });
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _msg = e.message ?? 'ত্রুটি হয়েছে');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isLogin ? 'লগইন' : 'নতুন একাউন্ট')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(controller: _email, decoration: const InputDecoration(labelText: 'ইমেইল')),
            TextField(
                controller: _pass,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'পাসওয়ার্ড')),
            const SizedBox(height: 16),
            ElevatedButton(
                onPressed: _submit,
                child: Text(_isLogin ? 'লগইন' : 'একাউন্ট খুলুন')),
            TextButton(
                onPressed: () => setState(() => _isLogin = !_isLogin),
                child: Text(_isLogin ? 'নতুন একাউন্ট খুলুন' : 'লগইন পাতায় যান')),
            Text(_msg, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  RewardedAd? _ad;
  String _msg = '';
  DateTime? _lastShown;
  int _adsToday = 0;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    RewardedAd.load(
      adUnitId: kTestAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => setState(() => _ad = ad),
        onAdFailedToLoad: (err) => setState(() => _msg = 'বিজ্ঞাপন লোড হয়নি। VPN বন্ধ করে চেষ্টা করুন।'),
      ),
    );
  }

  Future<void> _watchAd() async {
    if (_ad == null) {
      _loadAd();
      return;
    }
    final now = DateTime.now();
    if (_lastShown != null && now.difference(_lastShown!).inSeconds < 30) {
      setState(() => _msg = 'আরেকটি বিজ্ঞাপনের আগে ৩০ সেকেন্ড অপেক্ষা করুন।');
      return;
    }
    if (_adsToday >= 500) {
      setState(() => _msg = 'আজকের সীমা শেষ হয়েছে।');
      return;
    }
    final ad = _ad!;
    _ad = null;
    _lastShown = now;
    ad.show(onUserEarnedReward: (ad, reward) async {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final ref = FirebaseFirestore.instance.collection('users').doc(uid);
      final add = _adsToday < 100 ? 10 : (_adsToday < 200 ? 5 : 1);
      _adsToday++;
      await ref.update({
        'points': FieldValue.increment(add),
        'lastAdAt': FieldValue.serverTimestamp(),
      });
      setState(() => _msg = '+$add পয়েন্ট পেয়েছেন');
    });
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadAd();
      },
    );
  }

  Future<void> _withdraw() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final number = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: const Text('বিকাশ/নগদ নম্বর (১১ সংখ্যা)'),
          content: TextField(controller: c, keyboardType: TextInputType.phone),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('বাতিল')),
            TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('জমা দিন')),
          ],
        );
      },
    );
    if (number == null || !RegExp(r'^\d{11}$').hasMatch(number)) {
      setState(() => _msg = 'সঠিক ১১ সংখ্যার নম্বর দিন।');
      return;
    }
    await FirebaseFirestore.instance.collection('withdrawals').add({
      'uid': uid,
      'number': number,
      'amount': 100,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
    setState(() => _msg = 'উইথড্র অনুরোধ পাঠানো হয়েছে।');
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return Scaffold(
      appBar: AppBar(
        title: const Text('রিওয়ার্ড অ্যাপ'),
        actions: [
          IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => FirebaseAuth.instance.signOut()),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
              builder: (context, snap) {
                final pts = (snap.data?.data() as Map<String, dynamic>?)?['points'] ?? 0;
                return Text('আপনার পয়েন্ট: $pts',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold));
              },
            ),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: _watchAd, child: const Text('বিজ্ঞাপন দেখুন')),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _withdraw, child: const Text('উইথড্র অনুরোধ')),
            const SizedBox(height: 16),
            Text(_msg),
          ],
        ),
      ),
    );
  }
}
