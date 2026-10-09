import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/cartaauth.dart';
import 'settings/signin.dart';
import 'home/home.dart';

class Wrapper extends StatelessWidget {
  const Wrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final signedIn = context.watch<CartaAuth>().hasSavedAccount;

    return signedIn ? const HomePage() : const SignInPage();
  }
}
