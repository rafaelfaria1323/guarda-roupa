import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/product_import.dart';

/// `null` sem Supabase configurado: a importação não aparece.
final productImporterProvider = Provider<ProductImporter?>((ref) => null);
