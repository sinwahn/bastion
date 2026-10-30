# /etc/nixos/modules/bastion/bastion.py
# The bastion tool (the command "bastion", modules/bastion/bastion.nix): a
# status screen first, then the sections VMs, networks, devices,
# looking-glass and the broker; and the command line's words, which the help
# lists. This file is the start: the settings bastion.nix hands over (the
# first argument, a JSON file) read into the configuration, every object of
# the three layers built once, the command line run, and the one handler of
# a failure. The layers: user (the screens, the questions, the lines shown),
# model (the VMs, the stations, the networks, the configuration, the
# refusals), system (libvirt, the files, the programs run, the log).

import os
import sys
import traceback

from model.ConfigurationReading import ConfigurationReading
from model.GlassSettings import GlassSettings
from model.HostAccess import HostAccess
from model.LiveDataFile import LiveDataFile
from model.LiveDataFormat import LiveDataFormat
from model.Templates import Templates
from model.starts.FirstStart import FirstStart
from model.starts.OrdinaryStart import OrdinaryStart
from system.AnswerPoint import AnswerPoint
from system.CopyFolder import CopyFolder
from system.FirewallCheck import FirewallCheck
from system.GlassClientFile import GlassClientFile
from system.GlassClientPlaces import GlassClientPlaces
from system.HostFiles import HostFiles
from system.HostInternet import HostInternet
from system.HostWindows import HostWindows
from system.KernelRoutes import KernelRoutes
from system.LibvirtConnections import LibvirtConnections
from system.Log import Log
from system.NixDomains import NixDomains
from system.PrivilegedSteps import PrivilegedSteps
from system.ServiceUnits import ServiceUnits
from system.SharedMemoryDevice import SharedMemoryDevice
from system.ShellCommands import ShellCommands
from system.StickFiles import StickFiles
from system.SwitchPorts import SwitchPorts
from system.UplinkProfiles import UplinkProfiles
from system.WifiCheck import WifiCheck
from user.CommandLine import CommandLine
from user.HelpText import HelpText
from user.commands.CleanCommand import CleanCommand
from user.commands.ConsoleCommand import ConsoleCommand
from user.commands.ExchangeFilesCommand import ExchangeFilesCommand
from user.commands.ListCommand import ListCommand
from user.commands.ResolutionCommand import ResolutionCommand
from user.commands.ScreensCommand import ScreensCommand
from user.commands.SealCommand import SealCommand
from user.commands.SendCommand import SendCommand
from user.commands.StartCommand import StartCommand
from user.commands.TemplateCommand import TemplateCommand
from user.commands.TransfersCommand import TransfersCommand
from user.commands.VirtioFilesCommand import VirtioFilesCommand
from user.enums import ExitCode


def start():
    log = Log()
    try:
        access = HostAccess()
        access.log = log
        access.shell = ShellCommands(log)
        access.files = HostFiles(log)
        configuration = ConfigurationReading(access.files.read_json(sys.argv[1])).read()
        configuration.interpreter = sys.executable
        configuration.entry = os.path.abspath(__file__)
        configuration.settings_file = sys.argv[1]
        programs = configuration.programs
        access.configuration = configuration
        access.libvirt = LibvirtConnections(configuration.uri, log)
        access.nix_domains = NixDomains(access.files, log)
        access.live_format = LiveDataFormat(configuration.exchange.sends_to)
        access.live_data_file = LiveDataFile(access.files, configuration.live_data_file, access.live_format)
        access.copy_folder = CopyFolder(access.files, configuration.copy_folder, log)
        access.shared_memory = SharedMemoryDevice(access.files, log)
        access.service_units = ServiceUnits(access.shell, programs.systemctl, log)
        access.windows = HostWindows(access.shell, configuration.uri)
        access.privileged_steps = PrivilegedSteps(access.shell, programs.privileged, log)
        places = GlassClientPlaces()
        access.glass_settings = GlassSettings(GlassClientFile(access.files, places.system_file(), log),
                                              GlassClientFile(access.files, places.own_file(), log))
        access.internet = HostInternet(configuration.internet_target, configuration.internet_seconds, log)
        access.uplink_profiles = UplinkProfiles(access.shell, programs.nmcli)
        access.switch_ports = SwitchPorts(access.shell, programs.ip, programs.bridge)
        access.kernel_routes = KernelRoutes(access.shell, programs.ip)
        access.firewall_check = FirewallCheck(AnswerPoint(access.shell, programs.socat, configuration.firewall_check))
        access.wifi_check = WifiCheck(AnswerPoint(access.shell, programs.socat, configuration.wifi_check))
        access.stick_files = StickFiles(access.files)
        access.templates = Templates(configuration, access.files)
        command_line = CommandLine([ScreensCommand(access), ListCommand(access), TemplateCommand(access), SealCommand(access),
                                    StartCommand(access, OrdinaryStart()), StartCommand(access, FirstStart()),
                                    ConsoleCommand(access), ResolutionCommand(access), ExchangeFilesCommand(access),
                                    VirtioFilesCommand(access), SendCommand(access), TransfersCommand(access),
                                    CleanCommand(access)], HelpText(access))
        command_line.run(sys.argv[2:])
    except Exception as error:
        if isinstance(error, MemoryError):
            raise
        traceback.print_exception(error)
        log.print_lines()
        sys.exit(ExitCode.kStopped)
    sys.exit(command_line.exit_code())


if __name__ == "__main__":
    start()
