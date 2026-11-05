import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

// Google-এর টেস্ট আইডি। আসল আইডি পরে বসবে।
const String kTestAdUnitId = 'ca-app-pub-3940256099942544/5224354917';

// ৳ হার: ১০০০ পয়েন্ট = কত টাকা। এটা আপনি AdMob-এর আসল আয় দেখে ঠিক করবেন।
// ০ থাকলে উইথড্র বন্ধ থাকবে। এখন ইচ্ছে করেই ০ রাখা হয়েছে।
const int kTakaPer1000Points = 0;
const int kMinWithdrawPoints = 1000;
const int kDailyAdLimit = 500;

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
  bool _busy = false;

  String get _uid => FirebaseAuth.instance.currentUser!.uid;
  DocumentReference<Map<String, dynamic>> get _userRef =>
      FirebaseFirestore.instance.collection('users').doc(_uid);

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  String _dayKey() {
    final n = DateTime.now();
    return '${n.year}${n.month.toString().padLeft(2, '0')}${n.day.toString().padLeft(2, '0')}';
  }

  void _loadAd() {
    RewardedAd.load(
      adUnitId: kTestAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => setState(() => _ad = ad),
        onAdFailedToLoad: (err) =>
            setState(() => _msg = 'বিজ্ঞাপন লোড হয়নি। VPN বন্ধ করে চেষ্টা করুন।'),
      ),
    );
  }

  Future<void> _watchAd() async {
    if (_busy) return;
    if (kTakaPer1000Points == 0 && false) return; // পয়েন্ট ব্যবহার আলাদা, বিজ্ঞাপন চালু থাকবে
    if (_ad == null) {
      _loadAd();
      setState(() => _msg = 'বিজ্ঞাপন প্রস্তুত হচ্ছে, একটু পরে আবার চাপুন।');
      return;
    }
    final now = DateTime.now();
    if (_lastShown != null && now.difference(_lastShown!).inSeconds < 30) {
      setState(() => _msg = 'আরেকটি বিজ্ঞাপনের আগে ৩০ সেকেন্ড অপেক্ষা করুন।');
      return;
    }

    // দিনের সীমা যাচাই (ডেটাবেস থেকে)
    final snap = await _userRef.get();
    final d = snap.data() ?? {};
    final sameDay = d['dayKey'] == _dayKey();
    final todayCount = sameDay ? ((d['adCountToday'] as num?)?.toInt() ?? 0) : 0;
    if (todayCount >= kDailyAdLimit) {
      setState(() => _msg = 'আজকের বিজ্ঞাপনের সীমা শেষ হয়েছে।');
      return;
    }

    final ad = _ad!;
    _ad = null;
    _lastShown = now;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _loadAd();
      },
      onAdFailedToShowFullScreenContent: (a, e) {
        a.dispose();
        _loadAd();
      },
    );
    ad.show(onUserEarnedReward: (a, reward) {
      _grantReward();
    });
  }

  // বিজ্ঞাপন দেখার পুরস্কার: একটি ট্রানজেকশনে পয়েন্ট ও গণনা একসাথে বাড়ে
  Future<void> _grantReward() async {
    final today = _dayKey();
    setState(() => _busy = true);
    try {
      final add = await FirebaseFirestore.instance.runTransaction<int>((tx) async {
        final snap = await tx.get(_userRef);
        final d = snap.data() ?? {};
        final sameDay = d['dayKey'] == today;
        final count = sameDay ? ((d['adCountToday'] as num?)?.toInt() ?? 0) : 0;
        if (count >= kDailyAdLimit) return -1;
        final pts = (d['points'] as num?)?.toInt() ?? 0;
        final add = count < 100 ? 10 : (count < 200 ? 5 : 1);
        tx.update(_userRef, {
          'points': pts + add,
          'adCountToday': count + 1,
          'dayKey': today,
          'lastAdAt': FieldValue.serverTimestamp(),
        });
        return add;
      });
      setState(() => _msg = add < 0
          ? 'আজকের সীমা শেষ হয়েছে।'
          : '+$add পয়েন্ট পেয়েছেন');
    } catch (e) {
      setState(() => _msg = 'পুরস্কার যাচাই হয়নি। একটু পরে আবার চেষ্টা করুন।');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _withdraw() async {
    if (kTakaPer1000Points == 0) {
      setState(() => _msg = 'উইথড্র এখনো চালু হয়নি।');
      return;
    }
    final numCtrl = TextEditingController();
    final ptsCtrl = TextEditingController();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('উইথড্র অনুরোধ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: numCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'বিকাশ/নগদ নম্বর (১১ সংখ্যা)')),
            TextField(
                controller: ptsCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: 'পয়েন্ট (সর্বনিম্ন $kMinWithdrawPoints)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('বাতিল')),
          TextButton(
              onPressed: () => Navigator.pop(
                  ctx, {'n': numCtrl.text.trim(), 'p': ptsCtrl.text.trim()}),
              child: const Text('জমা দিন')),
        ],
      ),
    );
    if (result == null) return;

    final number = result['n'] ?? '';
    final amount = int.tryParse(result['p'] ?? '') ?? 0;
    if (!RegExp(r'^01[3-9]\d{8}$').hasMatch(number)) {
      setState(() => _msg = 'সঠিক ১১ সংখ্যার নম্বর দিন (01 দিয়ে শুরু)।');
      return;
    }
    if (amount < kMinWithdrawPoints) {
      setState(() => _msg = 'সর্বনিম্ন $kMinWithdrawPoints পয়েন্ট লাগবে।');
      return;
    }

    try {
      final withdrawRef = FirebaseFirestore.instance.collection('withdrawals').doc();
      final ok = await FirebaseFirestore.instance.runTransaction<bool>((tx) async {
        final snap = await tx.get(_userRef);
        final pts = (snap.data()?['points'] as num?)?.toInt() ?? 0;
        if (pts < amount) return false;
        // পয়েন্ট কাটা ও অনুরোধ তৈরি একসাথে
        tx.update(_userRef, {'points': pts - amount});
        tx.set(withdrawRef, {
          'uid': _uid,
          'number': number,
          'amount': amount,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        });
        return true;
      });
      setState(() => _msg = ok
          ? 'উইথড্র অনুরোধ পাঠানো হয়েছে। অনুমোদনের পর টাকা পাঠানো হবে।'
          : 'আপনার পয়েন্ট যথেষ্ট নেই।');
    } catch (e) {
      setState(() => _msg = 'উইথড্র অনুরোধ পাঠানো যায়নি। আবার চেষ্টা করুন।');
    }
  }

  @override
  Widget build(BuildContext context) {
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
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _userRef.snapshots(),
              builder: (context, snap) {
                final pts = (snap.data?.data()?['points'] as num?)?.toInt() ?? 0;
                return Text('আপনার পয়েন্ট: $pts',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold));
              },
            ),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: _watchAd, child: const Text('বিজ্ঞাপন দেখুন')),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _withdraw, child: const Text('উইথড্র অনুরোধ')),
            const SizedBox(height: 16),
            Text(_msg, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
