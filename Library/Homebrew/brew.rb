# typed: false
# frozen_string_literal: true

if ENV["HOMEBREW_STACKPROF"]
  require "rubygems"
  require "stackprof"
  StackProf.start(mode: :wall, raw: true)
end

raise "HOMEBREW_BREW_FILE was not exported! Please call bin/brew directly!" unless ENV["HOMEBREW_BREW_FILE"]
if $PROGRAM_NAME != __FILE__ && !$PROGRAM_NAME.end_with?("/bin/ruby-prof")
  raise "#{__FILE__} must not be loaded via `require`."
end

std_trap = trap("INT") { exit! 130 } # no backtrace thanks

# check ruby version before requiring any modules.
REQUIRED_RUBY_X, REQUIRED_RUBY_Y, = ENV.fetch("HOMEBREW_REQUIRED_RUBY_VERSION").split(".").map(&:to_i)
RUBY_X, RUBY_Y, = RUBY_VERSION.split(".").map(&:to_i)
if RUBY_X < REQUIRED_RUBY_X || (RUBY_X == REQUIRED_RUBY_X && RUBY_Y < REQUIRED_RUBY_Y)
  raise "Homebrew must be run under Ruby #{REQUIRED_RUBY_X}.#{REQUIRED_RUBY_Y}! " \
        "You're running #{RUBY_VERSION}."
end

require_relative "global"

begin
  trap("INT", std_trap) # restore default CTRL-C handler

  if ENV["CI"]
    $stdout.sync = true
    $stderr.sync = true
  end

  empty_argv = ARGV.empty?
  help_flag_list = %w[-h --help --usage -?]
  help_flag = !ENV["HOMEBREW_HELP"].nil?
  help_cmd_index = nil
  cmd = nil

  ARGV.each_with_index do |arg, i|
    break if help_flag && cmd

    if arg == "help" && !cmd
      # Command-style help: `help <cmd>` is fine, but `<cmd> help` is not.
      help_flag = true
      help_cmd_index = i
    elsif !cmd && help_flag_list.exclude?(arg)
      cmd = ARGV.delete_at(i)
      cmd = Commands::HOMEBREW_INTERNAL_COMMAND_ALIASES.fetch(cmd, cmd)
    end
  end

  ARGV.delete_at(help_cmd_index) if help_cmd_index

  require "cli/parser"
  args = Homebrew::CLI::Parser.new.parse(ARGV.dup.freeze, ignore_invalid_options: true)
  Context.current = args.context

  path = PATH.new(ENV.fetch("PATH"))
  homebrew_path = PATH.new(ENV.fetch("HOMEBREW_PATH"))

  # Add shared wrappers.
  path.prepend(HOMEBREW_SHIMS_PATH/"shared")
  homebrew_path.prepend(HOMEBREW_SHIMS_PATH/"shared")

  ENV["PATH"] = path

  require "commands"
  require "settings"

  internal_cmd = Commands.valid_internal_cmd?(cmd) || Commands.valid_internal_dev_cmd?(cmd) if cmd

  unless internal_cmd
    # Add contributed commands to PATH before checking.
    homebrew_path.append(Tap.cmd_directories)

    # External commands expect a normal PATH
    ENV["PATH"] = homebrew_path
  end

  # Usage instructions should be displayed if and only if one of:
  # - a help flag is passed AND a command is matched
  # - a help flag is passed AND there is no command specified
  # - no arguments are passed
  if empty_argv || help_flag
    require "help"
    Homebrew::Help.help cmd, remaining_args: args.remaining, empty_argv: empty_argv
    # `Homebrew::Help.help` never returns, except for unknown commands.
  end

  if internal_cmd || Commands.external_ruby_v2_cmd_path(cmd)
    Homebrew.send Commands.method_name(cmd)
  elsif (path = Commands.external_ruby_cmd_path(cmd))
    require?(path)
    exit Homebrew.failed? ? 1 : 0
  elsif Commands.external_cmd_path(cmd)
    %w[CACHE LIBRARY_PATH].each do |env|
      ENV["HOMEBREW_#{env}"] = Object.const_get("HOMEBREW_#{env}").to_s
    end
    exec "brew-#{cmd}", *ARGV
  else
    possible_tap = OFFICIAL_CMD_TAPS.find { |_, cmds| cmds.include?(cmd) }
    possible_tap = Tap.fetch(possible_tap.first) if possible_tap

    if !possible_tap ||
       possible_tap.installed? ||
       (blocked_tap = Tap.untapped_official_taps.include?(possible_tap.name))
      if blocked_tap
        onoe <<~EOS
          `brew #{cmd}` is unavailable because #{possible_tap.name} was manually untapped.
          Run `brew tap #{possible_tap.name}` to reenable `brew #{cmd}`.
        EOS
      end
      # Check for cask explicitly because it's very common in old guides
      odie "`brew cask` is no longer a `brew` command. Use `brew <command> --cask` instead." if cmd == "cask"
      odie "Unknown command: #{cmd}"
    end

    # Unset HOMEBREW_HELP to avoid confusing the tap
    with_env HOMEBREW_HELP: nil do
      tap_commands = []
      if File.exist?("/.dockerenv") ||
         Process.uid.zero? ||
         ((cgroup = Utils.popen_read("cat", "/proc/1/cgroup").presence) &&
          %w[azpl_job actions_job docker garden kubepods].none? { |type| cgroup.include?(type) })
        brew_uid = HOMEBREW_BREW_FILE.stat.uid
        tap_commands += %W[/usr/bin/sudo -u ##{brew_uid}] if Process.uid.zero? && !brew_uid.zero?
      end
      quiet_arg = args.quiet? ? "--quiet" : nil
      tap_commands += [HOMEBREW_BREW_FILE, "tap", *quiet_arg, possible_tap.name]
      safe_system(*tap_commands)
    end

    ARGV << "--help" if help_flag
    exec HOMEBREW_BREW_FILE, cmd, *ARGV
  end
rescue UsageError => e
  require "help"
  Homebrew::Help.help cmd, remaining_args: args.remaining, usage_error: e.message
rescue SystemExit => e
  onoe "Kernel.exit" if args.debug? && !e.success?
  $stderr.puts e.backtrace if args.debug?
  raise
rescue Interrupt
  $stderr.puts # seemingly a newline is typical
  exit 130
rescue BuildError => e
  Utils::Analytics.report_build_error(e)
  e.dump(verbose: args.verbose?)

  if e.formula.head? || e.formula.deprecated? || e.formula.disabled?
    reason = if e.formula.head?
      "was built from an unstable upstream --HEAD"
    elsif e.formula.deprecated?
      "is deprecated"
    elsif e.formula.disabled?
      "is disabled"
    end
    $stderr.puts <<~EOS
      #{e.formula.name}'s formula #{reason}.
      This build failure is expected behaviour.
      Do not create issues about this on Homebrew's GitHub repositories.
      Any opened issues will be immediately closed without response.
      Do not ask for help from MacHomebrew on Twitter.
      You may ask for help in Homebrew's discussions but are unlikely to receive a response.
      Try to figure out the problem yourself and submit a fix as a pull request.
      We will review it but may or may not accept it.
    EOS
  end

  exit 1
rescue RuntimeError, SystemCallError => e
  raise if e.message.empty?

  onoe e
  $stderr.puts e.backtrace if args.debug?

  exit 1
rescue MethodDeprecatedError => e
  onoe e
  if e.issues_url
    $stderr.puts "If reporting this issue please do so at (not Homebrew/brew or Homebrew/homebrew-core):"
    $stderr.puts "  #{Formatter.url(e.issues_url)}"
  end
  $stderr.puts e.backtrace if args.debug?
  exit 1
rescue Exception => e # rubocop:disable Lint/RescueException
  onoe e
  if internal_cmd && !OS.unsupported_configuration?
    if Homebrew::EnvConfig.no_auto_update?
      $stderr.puts "#{Tty.bold}Do not report this issue until you've run `brew update` and tried again.#{Tty.reset}"
    else
      $stderr.puts "#{Tty.bold}Please report this issue:#{Tty.reset}"
      $stderr.puts "  #{Formatter.url(OS::ISSUES_URL)}"
    end
  end
  $stderr.puts e.backtrace
  exit 1
else
  exit 1 if Homebrew.failed?
ensure
  if ENV["HOMEBREW_STACKPROF"]
    StackProf.stop
    StackProf.results("prof/stackprof.dump")
  end
end
