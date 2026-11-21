using System.Windows;
using Glance.Core.Tasks;
using Glance.Core.Widgets;

namespace Glance.App.Widgets;

/// <summary>What the Widget Market and Task Center ask of the app (implemented by <c>WidgetRunner</c>).</summary>
internal interface IWidgetHost
{
    /// <summary>Opens a finished task's result: media in Image / Video Inspect, text in the result window.</summary>
    void OpenResult(WidgetTaskRecord record);

    /// <summary>Opens the task's source item (Image / Video Inspect), when it still exists.</summary>
    void OpenSource(WidgetTaskRecord record);

    /// <summary>Runs a failed / cancelled task again (resumes without a new charge when possible).</summary>
    void Retry(WidgetTaskRecord record, Window? owner);

    /// <summary>Runs a text-only Widget command (opens its text input window).</summary>
    void RunText(WidgetManifest widget, WidgetCommand command, Window? owner);

    /// <summary>Opens the account window (sign in / credits).</summary>
    void ShowAccount(Window? owner);
}
