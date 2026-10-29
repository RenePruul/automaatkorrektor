using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Automation;
using System.Windows.Automation.Text;

internal static class Program
{
    private const string Canary = "KANAARILIND-123";
    private const int MaximumSelectionLength = 10_000;
    private static readonly TimeSpan ProbeTimeout = TimeSpan.FromSeconds(1);

    private static async Task<int> Main()
    {
        Console.WriteLine("PROTOTÜÜP — ei ole tootmiskood");
        Console.WriteLine($"Kirjuta Notepadi {Canary}, vali see ja hoia Notepad fookuses.");
        Console.WriteLine("Kontroll algab viie sekundi pärast. Valitud teksti ei väljastata.");

        for (var seconds = 5; seconds > 0; seconds--)
        {
            Console.WriteLine($"{seconds}...");
            await Task.Delay(TimeSpan.FromSeconds(1));
        }

        var completion = new TaskCompletionSource<ProbeResult>(
            TaskCreationOptions.RunContinuationsAsynchronously
        );
        var worker = new Thread(() => completion.TrySetResult(Probe()))
        {
            IsBackground = true,
            Name = "UI Automation probe",
        };
        worker.SetApartmentState(ApartmentState.MTA);

        var stopwatch = Stopwatch.StartNew();
        worker.Start();

        var finished = await Task.WhenAny(completion.Task, Task.Delay(ProbeTimeout));
        stopwatch.Stop();

        if (finished != completion.Task)
        {
            Console.WriteLine("FAIL: UI Automation ületas ühe sekundi ajalimiidi.");
            return 2;
        }

        var result = await completion.Task;
        Console.WriteLine($"Aeg: {stopwatch.ElapsedMilliseconds} ms");
        Console.WriteLine(result.Message);
        if (result.SelectionLength is { } length)
        {
            Console.WriteLine($"Valiku pikkus: {length} UTF-16 ühikut");
        }

        return result.Passed ? 0 : 1;
    }

    private static ProbeResult Probe()
    {
        try
        {
            var initialElement = AutomationElement.FocusedElement;
            if (initialElement is null)
            {
                return ProbeResult.Rejected("FAIL: fookuses element puudub.");
            }

            var initial = initialElement.Current;
            if (!initial.HasKeyboardFocus || !initial.IsEnabled || !initial.IsKeyboardFocusable)
            {
                return ProbeResult.Rejected("FAIL: element pole aktiivne ja kasutatav tekstiväli.");
            }

            if (initial.IsPassword)
            {
                return ProbeResult.Rejected("PASS: kaitstud väli lükati tagasi.", passed: true);
            }

            using var targetProcess = Process.GetProcessById(initial.ProcessId);
            if (!string.Equals(targetProcess.ProcessName, "notepad", StringComparison.OrdinalIgnoreCase))
            {
                return ProbeResult.Rejected("PASS: muu rakendus lükati tagasi.", passed: true);
            }

            if (IsHigherIntegrityThanCurrentProcess(targetProcess))
            {
                return ProbeResult.Rejected("PASS: kõrgendatud Notepad lükati tagasi.", passed: true);
            }

            if (initial.ControlType != ControlType.Edit && initial.ControlType != ControlType.Document)
            {
                return ProbeResult.Rejected("FAIL: Notepadi fookuses element pole Edit ega Document.");
            }

            if (!initialElement.TryGetCurrentPattern(TextPattern.Pattern, out var textPatternObject))
            {
                return ProbeResult.Rejected("FAIL: Notepadi element ei paku TextPatternit.");
            }

            var textPattern = (TextPattern)textPatternObject;
            if (textPattern.SupportedTextSelection == SupportedTextSelection.None)
            {
                return ProbeResult.Rejected("FAIL: Notepadi element ei toeta tekstivalikut.");
            }

            var ranges = textPattern.GetSelection();
            if (ranges.Length != 1)
            {
                return ProbeResult.Rejected("PASS: null või mitu valikut lükati tagasi.", passed: true);
            }

            var range = ranges[0];
            if (
                range.CompareEndpoints(
                    TextPatternRangeEndpoint.Start,
                    range,
                    TextPatternRangeEndpoint.End
                ) == 0
            )
            {
                return ProbeResult.Rejected("PASS: tühi valik lükati tagasi.", passed: true);
            }

            if (!IsEditable(initialElement, range))
            {
                return ProbeResult.Rejected("PASS: muudetavuseta väli lükati tagasi.", passed: true);
            }

            var selectedText = range.GetText(MaximumSelectionLength + 1);
            if (selectedText.Length > MaximumSelectionLength)
            {
                return ProbeResult.Rejected("PASS: liiga pikk valik lükati tagasi.", passed: true);
            }

            if (string.IsNullOrWhiteSpace(selectedText))
            {
                return ProbeResult.Rejected("PASS: sisuta valik lükati tagasi.", passed: true);
            }

            var finalElement = AutomationElement.FocusedElement;
            if (finalElement is null || !SameElement(initialElement, finalElement))
            {
                return ProbeResult.Rejected("PASS: fookuse muutumisel visati valik ära.", passed: true);
            }

            var final = finalElement.Current;
            if (!final.HasKeyboardFocus || final.IsPassword || final.ProcessId != initial.ProcessId)
            {
                return ProbeResult.Rejected("PASS: elemendi omaduste muutumisel visati valik ära.", passed: true);
            }

            var matchesCanary = string.Equals(selectedText, Canary, StringComparison.Ordinal);
            var selectionLength = selectedText.Length;
            selectedText = string.Empty;

            return matchesCanary
                ? ProbeResult.Accepted("PASS: täpne kanaarilinnu valik loeti ilma seda väljastamata.", selectionLength)
                : ProbeResult.Rejected(
                    "FAIL: valik loeti, kuid see ei vastanud kanaarilinnule.",
                    selectionLength: selectionLength
                );
        }
        catch (ElementNotAvailableException)
        {
            return ProbeResult.Rejected("PASS: kadunud UI Automationi element lükati tagasi.", passed: true);
        }
        catch (UnauthorizedAccessException)
        {
            return ProbeResult.Rejected("PASS: ligipääsmatu element lükati tagasi.", passed: true);
        }
        catch (COMException exception)
        {
            return ProbeResult.Rejected($"FAIL: UI Automationi COM-viga 0x{exception.HResult:X8}.");
        }
        catch (Exception exception)
        {
            return ProbeResult.Rejected($"FAIL: ootamatu {exception.GetType().Name}.");
        }
    }

    private static bool IsEditable(AutomationElement element, TextPatternRange range)
    {
        if (element.TryGetCurrentPattern(ValuePattern.Pattern, out var valuePatternObject))
        {
            return !((ValuePattern)valuePatternObject).Current.IsReadOnly;
        }

        var attribute = range.GetAttributeValue(TextPattern.IsReadOnlyAttribute);
        return attribute is bool isReadOnly && !isReadOnly;
    }

    private static bool SameElement(AutomationElement first, AutomationElement second)
    {
        var firstId = first.GetRuntimeId();
        var secondId = second.GetRuntimeId();
        return firstId is not null && secondId is not null && firstId.SequenceEqual(secondId);
    }

    private static bool IsHigherIntegrityThanCurrentProcess(Process targetProcess)
    {
        var currentIntegrity = GetIntegrityLevel(Process.GetCurrentProcess());
        var targetIntegrity = GetIntegrityLevel(targetProcess);
        return targetIntegrity > currentIntegrity;
    }

    private static uint GetIntegrityLevel(Process process)
    {
        if (!OpenProcessToken(process.Handle, TokenQuery, out var token))
        {
            throw new UnauthorizedAccessException();
        }

        try
        {
            GetTokenInformation(token, TokenIntegrityLevel, IntPtr.Zero, 0, out var requiredLength);
            if (requiredLength == 0)
            {
                throw new UnauthorizedAccessException();
            }

            var buffer = Marshal.AllocHGlobal(requiredLength);
            try
            {
                if (!GetTokenInformation(token, TokenIntegrityLevel, buffer, requiredLength, out _))
                {
                    throw new UnauthorizedAccessException();
                }

                var label = Marshal.PtrToStructure<TokenMandatoryLabel>(buffer);
                var countPointer = GetSidSubAuthorityCount(label.Label.Sid);
                if (countPointer == IntPtr.Zero)
                {
                    throw new UnauthorizedAccessException();
                }

                var count = Marshal.ReadByte(countPointer);
                if (count == 0)
                {
                    throw new UnauthorizedAccessException();
                }

                var ridPointer = GetSidSubAuthority(label.Label.Sid, (uint)(count - 1));
                if (ridPointer == IntPtr.Zero)
                {
                    throw new UnauthorizedAccessException();
                }

                return unchecked((uint)Marshal.ReadInt32(ridPointer));
            }
            finally
            {
                Marshal.FreeHGlobal(buffer);
            }
        }
        finally
        {
            CloseHandle(token);
        }
    }

    private const uint TokenQuery = 0x0008;
    private const int TokenIntegrityLevel = 25;

    [StructLayout(LayoutKind.Sequential)]
    private struct SidAndAttributes
    {
        public IntPtr Sid;
        public uint Attributes;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct TokenMandatoryLabel
    {
        public SidAndAttributes Label;
    }

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool OpenProcessToken(IntPtr processHandle, uint desiredAccess, out IntPtr tokenHandle);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool GetTokenInformation(
        IntPtr tokenHandle,
        int tokenInformationClass,
        IntPtr tokenInformation,
        int tokenInformationLength,
        out int returnLength
    );

    [DllImport("advapi32.dll")]
    private static extern IntPtr GetSidSubAuthorityCount(IntPtr sid);

    [DllImport("advapi32.dll")]
    private static extern IntPtr GetSidSubAuthority(IntPtr sid, uint subAuthority);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr handle);

    private sealed record ProbeResult(bool Passed, string Message, int? SelectionLength)
    {
        public static ProbeResult Accepted(string message, int selectionLength) =>
            new(true, message, selectionLength);

        public static ProbeResult Rejected(
            string message,
            bool passed = false,
            int? selectionLength = null
        ) => new(passed, message, selectionLength);
    }
}
