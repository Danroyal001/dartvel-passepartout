// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

import 'package:flutter/material.dart';
import '../../../dartvel_client/dartvel_client.dart';

/// Full-screen viewer for long cryptographic or configuration content
/// (CA certificate, client certificate, client key, TLS wrap key, data ciphers, XOR):
/// the kit's read-only [PSLongContentPage]. The module view opens it by URL,
/// `/profiles/<id>/modules/<moduleId>/<section>` (see `openVPNSubpage`).
@DVFunctionalWidget()
Widget _openVPNContentScreen(BuildContext context, {required String title, required String content}) =>
    PSLongContentPage(title: title, text: content);
