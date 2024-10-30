import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

const defaultWebhookUrl =
    'https://prod-108.westus.logic.azure.com:443/workflows/3bc094ec689345609094ff63ad583c46/triggers/manual/paths/invoke?api-version=2016-06-01&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=da79bLYuDCu6tAvMQWMSqt5bmzbxrxNy3BI5cJ71lQw';
const defaulttoken = "";

Timer animateLoading() {
  final frames = ['-', '\\', '|', '/'];
  var i = 0;
  var maxLength = 10;

  final timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
    stdout.write('\r${frames[i]}');
    i = (i + 1) % frames.length;
    maxLength--;
    if (maxLength == 0) {
      stdout.write('\n');
      maxLength = 10;
    }
  });

  return timer;
}

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
      defaultsTo: true,
      help: 'Show additional command output.',
    )
    ..addFlag(
      'version',
      negatable: false,
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
      mandatory: false,
      defaultsTo: defaulttoken,
      abbr: 'o',
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
  final task = (args['task'] as String?)?.replaceAll('=', '');
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
  List<String> urlsApps = [];

  if (appType == 'apk' || appType == 'both') {
    final animationtimer = animateLoading();
    final outPutFilePath = await buildApp('apk', appName, verbose);
    urlsApps.add(await uploadToOneDrive(
      outPutFilePath,
      task,
      verbose,
      onedriveToken,
    ));
    animationtimer.cancel();
  }

  if (appType == 'ios' || appType == 'both') {
    final animationtimer = animateLoading();

    final outPutFilePath = await buildApp('ipa', appName, verbose);
    urlsApps.add(await uploadToOneDrive(
      outPutFilePath,
      task,
      verbose,
      onedriveToken,
    ));
    animationtimer.cancel();
  }

  final animationtimer = animateLoading();

  await sendMessageToTeams(
    'Build $appName para $appType concluído e disponível no OneDrive em ${urlsApps.join(', ')}',
    verbose,
    webhookUrl,
  );
  animationtimer.cancel();
}

Future<String> buildApp(String appType, String appName, bool verbose) async {
  final buildType = appType == 'apk' ? 'apk' : 'ipa';
  final buildCommand = 'build $buildType --release --build-name=$appName';

  if (verbose) {
    print('Executing build command: $buildCommand');
    print('Building $appType...');
    print('Current directory: ${Directory.current}');
  }
  // printar o que o comando flutter build esta retornando

  final process = await Process.run(
    'flutter',
    buildCommand.split(' '),
  );
  if (process.exitCode != 0) {
    print('Error building $appType: ${process.stderr}');
    exit(1);
  }

  final buildPath = 'build/app/outputs/flutter-apk/app-release.apk';
  if (verbose) print('Build $appType concluído e salvo em $buildPath.');
  return buildPath;
}

Future<String> uploadToOneDrive(
  String filePath,
  String drivePath,
  bool verbose,
  String token,
) async {
  final onedriveApiUrl = 'https://graph.microsoft.com/v1.0/me/drive/root:';

  final file = File(filePath);

  if (!file.existsSync()) {
    print('Arquivo não encontrado: $filePath');
    return throw Exception('Arquivo não encontrado: $filePath');
  }

  final fileName = path.basename(filePath);
  final uploadUrl = '$onedriveApiUrl/$drivePath/$fileName:/content';

  if (verbose) print('Uploading $fileName to OneDrive at $uploadUrl');

  final response = await http.put(
    Uri.parse(uploadUrl),
    headers: {
      'Authorization': 'Bearer $defaulttoken',
      'Content-Type': 'text/plain',
    },
    body: file.readAsBytesSync(),
  );

  if (response.statusCode == 201) {
    if (verbose) {
      print('Upload do arquivo $fileName para o OneDrive concluído.');
    }
    final jsonResponse = jsonDecode(response.body);
    return jsonResponse['@microsoft.graph.downloadUrl'] as String;
  } else {
    if (verbose) {
      print('Erro no upload para o OneDrive: ${response.body}');
    }
    return throw Exception('Erro no upload para o OneDrive: ${response.body}');
  }
}

Future<void> sendMessageToTeams(
    String message, bool verbose, String webhookUrl) async {
  if (verbose) print('Sending message to Teams: $message');

  final response = await http.post(
    Uri.parse(webhookUrl),
    headers: {
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'content': message,
    }),
  );

  if (response.statusCode == 200) {
    if (verbose) {
      print('Mensagem enviada com sucesso para o Teams.');
    }
  } else {
    if (verbose) {
      print('Erro ao enviar mensagem para o Teams: ${response.body}');
    }
    throw Exception('Erro ao enviar mensagem para o Teams: ${response.body}');
  }
}
