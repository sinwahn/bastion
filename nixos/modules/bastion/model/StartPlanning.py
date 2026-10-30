from model.HostThreads import HostThreads
from model.Refusals import Refusals
from model.StartPlan import StartPlan
from model.StateVms import StateVms


class StartPlanning:
    """A start of a VM, for the start screen and for the command line's start and first."""

    def __init__(self, configuration):
        self.configuration = configuration

    def plan(self, state, vm, start):
        vms = StateVms(state)
        plan = StartPlan()
        plan.refusals = Refusals(self.configuration).of_start(state.host, vms.running(), vm)
        for device in vms.given_card(vm):
            if device.holders:
                plan.refusals.append(f"{device.holders[0]} holds the {device.name}. Shut it down first.")
        if plan.refusals:
            return plan
        self._plan_pins(plan, state, vm)
        plan.lines += start.plan_lines()
        plan.vsock = self._free_vsock(vms)
        return plan

    def _plan_pins(self, plan, state, vm):
        threads = HostThreads(state.host)
        preference = threads.preference_of(vm.pins)
        taken = StateVms(state).taken_without(vm.name)
        pinned = threads.pins(vm.vcpus, preference, taken)
        plan.pins = pinned.threads
        plan.lines = [f"{vm.name} starts on {vm.vcpus} threads: {threads.kinds_text(pinned.threads)}."]
        if not pinned.shared:
            return
        shared = ', '.join(pinned.shared)
        if preference.shares_fast_only(pinned.threads, taken, state.host.kinds):
            plan.lines.append(f"It shares the fast cores with {shared}: fast-first VMs share them.")
        else:
            plan.lines.append(f"No core is free for all its threads: it shares cores with {shared}.")

    def _free_vsock(self, vms):
        """The lowest number from the settings' vsockFirst up that no running VM's live definition holds."""
        held = {vm.live_vsock for vm in vms.running()}
        number = self.configuration.vsock_first
        while number in held:
            number += 1
        return number

    configuration = None
