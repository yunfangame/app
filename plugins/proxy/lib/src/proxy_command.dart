import 'dart:io';

import 'package:flutter/foundation.dart';

const proxyHost = '127.0.0.1';

typedef ProxyProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      bool runInShell,
    });

typedef ProxyExecutableChecker = Future<bool> Function(String executable);

@immutable
class ProxyCommand {
  final String executable;
  final List<String> args;
  final bool runInShell;

  ProxyCommand(this.executable, List<String> args, {this.runInShell = false})
    : args = List.unmodifiable(args);
}

@immutable
class ProxyCommandResult {
  const ProxyCommandResult({
    required this.success,
    this.command,
    this.processResult,
    this.exception,
  });

  final bool success;
  final ProxyCommand? command;
  final ProcessResult? processResult;
  final ProcessException? exception;
}

class ProxyCommandRunner {
  final ProxyProcessRunner _processRunner;

  ProxyCommandRunner(this._processRunner);

  Future<ProcessResult> process(
    String executable,
    List<String> arguments, {
    bool runInShell = false,
  }) {
    return _processRunner(executable, arguments, runInShell: runInShell);
  }

  Future<bool> run(Iterable<ProxyCommand> commands) async =>
      (await runDetailed(commands)).success;

  Future<ProxyCommandResult> runDetailed(
    Iterable<ProxyCommand> commands,
  ) async {
    ProxyCommand? lastCommand;
    ProcessResult? lastResult;
    for (final command in commands) {
      try {
        final result = await process(
          command.executable,
          command.args,
          runInShell: command.runInShell,
        );
        if (result.exitCode != 0) {
          return ProxyCommandResult(
            success: false,
            command: command,
            processResult: result,
          );
        }
        lastCommand = command;
        lastResult = result;
      } on ProcessException catch (error) {
        return ProxyCommandResult(
          success: false,
          command: command,
          exception: error,
        );
      }
    }
    return ProxyCommandResult(
      success: lastCommand != null,
      command: lastCommand,
      processResult: lastResult,
    );
  }
}
