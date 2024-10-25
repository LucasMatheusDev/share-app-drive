import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

const defaultWebhookUrl = 'YOUR_TEAMS_WEBHOOK_URL';

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Print this usage information.',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Show additional command output.',
    )
    ..addFlag(
      'version',
      negatable: false,
      defaultsTo: true,
      help: 'Print the tool version.',
    )
    ..addOption(
      'task',
      abbr: 't',
      mandatory: true,
      help: 'The task identifier for the build.',
    )
    ..addOption(
      'app',
      abbr: 'a',
      mandatory: true,
      allowed: ['apk', 'ios', 'both'],
      help: 'The type of app to build (apk, ios, both).',
    )
    ..addOption(
      'name',
      abbr: 'n',
      mandatory: true,
      help: 'The name of the version for the app.',
    )
    ..addOption(
      'webhook',
      abbr: 'w',
      defaultsTo: defaultWebhookUrl,
      help: 'The Teams webhook URL to send the message.',
    )
    ..addOption(
      'onedrive-token',
      mandatory: true,
      abbr: 'ot',
      help: 'The OneDrive access token to upload the app.\n'
          'Find token in https://developer.microsoft.com/en-us/graph/graph-explorer',
    );

  final args = parser.parse(arguments);

  if (args['help'] as bool) {
    print(parser.usage);
    exit(0);
  }

  if (args['version'] as bool) {
    print('Tool version: 1.0.0');
    exit(0);
  }

  final verbose = args['verbose'] as bool;
  final task = args['task'] as String?;
  final appType = args['app'] as String?;
  final appName = args['name'] as String?;
  final webhookUrl = args['webhook'] ?? defaultWebhookUrl;
  final onedriveToken = args['onedrive-token'] as String?;

  if (task == null ||
      appType == null ||
      appName == null ||
      onedriveToken == null) {
    print('Error: Missing required arguments.');
    print(parser.usage);
    exit(1);
  }

  final outputDir = Directory(path.join('build', task.toUpperCase()));
  if (!await outputDir.exists()) {
    await outputDir.create(recursive: true);
  }

  if (appType == 'apk' || appType == 'both') {
    await buildApp('apk', appName, outputDir, verbose);
  }

  if (appType == 'ios' || appType == 'both') {
    await buildApp('ipa', appName, outputDir, verbose);
  }

  await uploadToOneDrive(outputDir, task, verbose, onedriveToken);
  await sendMessageToTeams(
    'Build $appName para $appType concluído e disponível no OneDrive.',
    verbose,
    webhookUrl,
  );
}

Future<void> buildApp(
    String appType, String appName, Directory outputDir, bool verbose) async {
  final buildType = appType == 'apk' ? 'apk' : 'ipa';
  final buildCommand =
      'flutter build $buildType --release --build-name=$appName --output-dir=${outputDir.path}';

  if (verbose) print('Executing build command: $buildCommand');

  final process = await Process.run('bash', ['-c', buildCommand]);
  if (process.exitCode != 0) {
    print('Error building $appType: ${process.stderr}');
    exit(1);
  }

  final buildPath = outputDir.path;

  if (verbose) print('Build $appType concluído e salvo em $buildPath.');
}

Future<void> uploadToOneDrive(
  Directory outputDir,
  String folderName,
  bool verbose,
  String token,
) async {
  final onedriveApiUrl = 'https://graph.microsoft.com/v1.0/drive/root:/';

  for (var file in outputDir.listSync()) {
    final fileName = path.basename(file.path);
    final uploadUrl = '$onedriveApiUrl$folderName/$fileName:/content';

    if (verbose) print('Uploading $fileName to OneDrive at $uploadUrl');

    final response = await http.put(
      Uri.parse(uploadUrl),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/octet-stream',
      },
      body: await File(file.path).readAsBytes(),
    );

    if (response.statusCode == 201) {
      if (verbose) {
        print('Upload do arquivo $fileName para o OneDrive concluído.');
      }
    } else {
      print('Erro no upload para o OneDrive: ${response.body}');
    }
  }
}

Future<void> sendMessageToTeams(
    String message, bool verbose, String webhookUrl) async {
  if (verbose) print('Sending message to Teams: $message');

  final response = await http.post(
    Uri.parse(webhookUrl),
    headers: {'Content-Type': 'application/json'},
    body: '{"content": "$message"}',
  );

  if (response.statusCode == 200) {
    if (verbose) print('Mensagem enviada ao Teams.');
  } else {
    print('Erro ao enviar mensagem ao Teams: ${response.body}');
  }
}
