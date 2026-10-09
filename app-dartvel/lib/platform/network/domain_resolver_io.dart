// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev
import 'dart:io';

Future<List<String>> resolveDomain(String domain) async =>
    (await InternetAddress.lookup(domain).timeout(const Duration(seconds: 5))).map((address) => address.address).toList();
