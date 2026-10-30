"""Safety checks for profile-only renewal; tests never contact a real device."""
from datetime import datetime, timedelta, timezone
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import TestCase, main
from unittest.mock import patch
import hashlib
import json
import plistlib
from types import SimpleNamespace
import renew_phone as renewal
from schedule_renewal import calendar_fields, job

class RenewalTests(TestCase):
    def setUp(self):
        self.temp=TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.home=Path(self.temp.name)
        self.entitlements={"application-identifier":"TEAM.com.example.snapbridge.camera"}
        self.config=dict(team="TEAM",bundle_id="com.example.snapbridge.camera",device_udid="PHONE",build_version="7",marketing_version="0.5.0",installed_certificate_sha256=[hashlib.sha256(b"certificate").hexdigest()],expected_profile_entitlements=self.entitlements)
        self.app=self.home/"Ready.app";self.app.mkdir()
        (self.app/"Info.plist").write_bytes(plistlib.dumps(dict(CFBundleIdentifier=self.config["bundle_id"],CFBundleVersion="7")))
        (self.app/"embedded.mobileprovision").write_bytes(b"signed-profile-bytes")
        self.profile=dict(Entitlements=self.entitlements,ProvisionedDevices=["PHONE"],DeveloperCertificates=[b"certificate"],ExpirationDate=renewal.now()+timedelta(days=7),UUID="fresh")
        self.metadata=dict(CFBundleIdentifier=self.config["bundle_id"],CFBundleVersion="7",Path="unchanged/app",Container="unchanged/data")

    def test_healthy_signing_does_not_contact_the_phone_or_server(self):
        state=dict(installed_expiry=renewal.stamp(renewal.now()+timedelta(days=6)))
        with patch.object(renewal,"run") as command:
            self.assertEqual(renewal.renew(self.config,state,self.home)[0],"healthy")
            command.assert_not_called()

    def test_wrong_device_or_team_profile_is_rejected(self):
        for change in [dict(ProvisionedDevices=["OTHER"]),dict(Entitlements={"application-identifier":"OTHER.app"})]:
            with patch.object(renewal,"profile",return_value={**self.profile,**change}),patch.object(renewal,"run") as command:
                with self.assertRaises(renewal.RenewalError):renewal.validate_app(self.app,self.config,renewal.now())
                command.assert_not_called()

    def test_different_signing_certificate_never_triggers_reinstallation(self):
        with patch.object(renewal,"profile",return_value={**self.profile,"DeveloperCertificates":[b"another certificate"]}),patch.object(renewal,"run") as command:
            with self.assertRaises(renewal.RenewalError) as error:renewal.validate_app(self.app,self.config,renewal.now())
            self.assertEqual(error.exception.status,"certificate_changed");command.assert_not_called()

    def test_different_build_is_rejected(self):
        (self.app/"Info.plist").write_bytes(plistlib.dumps(dict(CFBundleIdentifier=self.config["bundle_id"],CFBundleVersion="8")))
        with patch.object(renewal,"profile",return_value=self.profile),patch.object(renewal,"run") as command:
            with self.assertRaises(renewal.RenewalError):renewal.validate_app(self.app,self.config,renewal.now())
            command.assert_not_called()

    def test_stale_cached_profile_is_not_mistaken_for_renewal(self):
        with patch.object(renewal,"profile",return_value={**self.profile,"ExpirationDate":renewal.now()+timedelta(days=3)}):
            with self.assertRaises(renewal.RenewalError) as error:renewal.validate_app(self.app,self.config,renewal.now()+timedelta(days=5))
            self.assertEqual(error.exception.status,"profile_not_extended")

    def test_raw_profile_validation_needs_no_app_signing_key(self):
        path=self.home/"ready.mobileprovision";path.write_bytes(b"profile")
        with patch.object(renewal,"profile",return_value=self.profile),patch.object(renewal,"run") as command:
            profile,info=renewal.validate_app(path,self.config,renewal.now())
            self.assertEqual(profile,self.profile);self.assertEqual(info["CFBundleVersion"],"7")
            command.assert_not_called()

    def test_profile_request_stops_xcode_as_soon_as_the_signed_profile_exists(self):
        original_app_info=(self.app/"Info.plist").read_bytes()
        cache=self.home/"Library/Developer/Xcode/UserData/Provisioning Profiles";cache.mkdir(parents=True)
        process=SimpleNamespace(pid=12345,returncode=None)
        process.poll=lambda:process.returncode
        process.wait=lambda timeout:process.returncode
        def start(*args,**kwargs):
            (cache/"fresh.mobileprovision").write_bytes(b"signed-profile")
            return process
        def stop(*args):process.returncode=-2
        with patch.object(renewal.Path,"home",return_value=self.home),patch.object(renewal.subprocess,"Popen",side_effect=start),patch.object(renewal.os,"killpg",side_effect=stop) as kill,patch.object(renewal,"profile",return_value=self.profile):
            ready=renewal.build_fresh({**self.config,"source_hashes":{}},self.home)
        self.assertEqual(ready.read_bytes(),b"signed-profile")
        self.assertEqual(ready.name,"Ready.mobileprovision")
        self.assertEqual((self.app/"Info.plist").read_bytes(),original_app_info)
        kill.assert_called_once_with(12345,renewal.signal.SIGINT)

    def test_untrusted_device_does_not_initiate_pairing(self):
        with patch.object(renewal,"run",return_value=(1,"not paired")) as command:
            with self.assertRaises(renewal.RenewalError):renewal.installed_app(self.config,self.home)
            self.assertEqual(command.call_count,1)
            self.assertEqual(command.call_args.args[0][-1],"validate")

    def test_removed_app_is_not_reinstalled(self):
        with patch.object(renewal,"run",side_effect=[(0,"trusted"),(0,plistlib.dumps([]).decode())]):
            with self.assertRaises(renewal.RenewalError) as error:renewal.installed_app(self.config,self.home)
            self.assertEqual(error.exception.status,"app_removed")

    def test_missing_wifi_device_starts_only_standard_apple_discovery(self):
        responses=[(1,"No device found with udid PHONE"),(0,""),(0,"paired"),(0,plistlib.dumps([self.metadata]).decode())]
        with patch.object(renewal,"run",side_effect=responses) as command,patch.object(renewal.time,"sleep"):
            self.assertEqual(renewal.installed_app(self.config,self.home),self.metadata)
            self.assertEqual(command.call_args_list[1].args[0][:2],["/bin/launchctl","kickstart"])
            self.assertTrue(command.call_args_list[1].args[0][-1].endswith("/com.apple.AMPDevicesAgent"))
            self.assertNotIn("-k",command.call_args_list[1].args[0])

    def test_zero_exit_status_with_rejected_profile_does_not_advance_expiry(self):
        old=renewal.stamp(renewal.now()-timedelta(days=1));state=dict(installed_expiry=old)
        with patch.object(renewal,"installed_app",return_value=self.metadata),patch.object(renewal,"validate_app",return_value=(self.profile,{"CFBundleVersion":"7"})),patch.object(renewal,"run",return_value=(0,"Could not install profile")):
            with self.assertRaises(renewal.RenewalError):renewal.renew(self.config,state,self.home,True)
        self.assertEqual(state["installed_expiry"],old);self.assertNotIn("last_success",state)

    def profile_commands(self,command,**kwargs):
        if command[-2]=="install":return 0,"Profile installed successfully."
        if "copy" in command:
            (Path(command[-1])/"fresh.mobileprovision").write_bytes(b"signed-profile-bytes")
            return 0,"Copied."
        raise AssertionError("Unexpected command: "+str(command))

    def test_success_requires_profile_readback_and_preserves_app_and_data(self):
        with patch.object(renewal,"installed_app",return_value=self.metadata),patch.object(renewal,"validate_app",return_value=(self.profile,{"CFBundleVersion":"7"})),patch.object(renewal,"run",side_effect=self.profile_commands) as command:
            state={};self.assertEqual(renewal.renew(self.config,state,self.home,True)[0],"renewed")
            self.assertEqual(state["renewal_mode"],"profile_only");self.assertTrue(state["app_and_data_container_unchanged"])
            for call in command.call_args_list:
                args=call.args[0]
                self.assertEqual(args[0],"/opt/homebrew/bin/ideviceprovision")
                self.assertIn("-n",args)
                self.assertNotIn("remove",args);self.assertNotIn("launch",args)

    def test_changed_data_container_stops_the_schedule(self):
        with patch.object(renewal,"installed_app",side_effect=[self.metadata,{**self.metadata,"Container":"changed"}]),patch.object(renewal,"validate_app",return_value=(self.profile,{"CFBundleVersion":"7"})),patch.object(renewal,"run",side_effect=self.profile_commands):
            state={}
            with self.assertRaises(renewal.RenewalError):renewal.renew(self.config,state,self.home,True)
            self.assertNotIn("last_success",state)

    def test_full_renewal_can_request_a_new_profile_instead_of_reusing_one(self):
        with patch.object(renewal,"installed_app",return_value=self.metadata),patch.object(renewal,"build_fresh",return_value=self.app) as build,patch.object(renewal,"validate_app",return_value=(self.profile,{"CFBundleVersion":"7"})),patch.object(renewal,"run",side_effect=self.profile_commands):
            self.assertEqual(renewal.renew(self.config,{},self.home,force=True,fresh_profile=True)[0],"renewed")
            build.assert_called_once_with(self.config,self.home)

    def test_missing_profile_readback_is_not_reported_as_success(self):
        with patch.object(renewal,"installed_app",return_value=self.metadata),patch.object(renewal,"validate_app",return_value=(self.profile,{"CFBundleVersion":"7"})),patch.object(renewal,"run",side_effect=[(0,"installed successfully"),(1,"not found")]):
            with self.assertRaises(renewal.RenewalError):renewal.renew(self.config,{},self.home,True)

    def test_schedule_is_a_calendar_date_without_polling(self):
        deadline=renewal.now()+timedelta(days=5);data=job(self.home,deadline)
        self.assertEqual(data["StartCalendarInterval"],calendar_fields(deadline));self.assertNotIn("StartInterval",data)
        self.assertFalse(data["RunAtLoad"]);self.assertEqual(data["ProcessType"],"Background")
        self.assertEqual(data["ProgramArguments"][:5],["/usr/bin/open","-g","-j","-W","-n"])

    def test_calendar_never_runs_seconds_before_renewal_is_due(self):
        # Include a day boundary and a DST change: round in UTC before converting.
        for deadline in [datetime(2026,11,4,2,46,4,tzinfo=timezone.utc),
                         datetime(2026,11,1,5,59,59,tzinfo=timezone.utc)]:
            expected=(deadline+timedelta(minutes=1)).replace(second=0,microsecond=0).astimezone()
            self.assertEqual(calendar_fields(deadline),dict(Month=expected.month,Day=expected.day,Hour=expected.hour,Minute=expected.minute))

    def test_exact_minute_is_not_delayed(self):
        deadline=datetime(2026,11,4,2,46,tzinfo=timezone.utc)
        local=deadline.astimezone()
        self.assertEqual(calendar_fields(deadline),dict(Month=local.month,Day=local.day,Hour=local.hour,Minute=local.minute))

if __name__=="__main__":main()
