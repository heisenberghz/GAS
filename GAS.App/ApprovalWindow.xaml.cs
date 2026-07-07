using System;
using System.Windows;
using System.Windows.Media;
using GAS.Core;

namespace GAS.App
{
    [System.Runtime.Versioning.SupportedOSPlatform("windows")]
    public partial class ApprovalWindow : Wpf.Ui.Controls.FluentWindow
    {
        public string RequestId { get; }
        public string UserDecision { get; private set; } = "deny";

        /// <summary>
        /// Creates the approval dialog.
        /// </summary>
        /// <param name="requestId">The SSE request ID to reply with.</param>
        /// <param name="permissionType">Human-readable tool type (e.g. "Terminal Command").</param>
        /// <param name="detail">Command/action detail string shown in monospace.</param>
        /// <param name="workingDir">The current working directory of the agent. Pass null to hide.</param>
        /// <param name="riskLevel">One of "Low", "Medium", or "High". Defaults to "Medium".</param>
        public ApprovalWindow(string requestId, string permissionType, string detail,
                              string? workingDir = null, string? riskLevel = null)
        {
            InitializeComponent();

            try
            {
                Wpf.Ui.Controls.WindowBackdrop.ApplyBackdrop(this, Wpf.Ui.Controls.WindowBackdropType.Mica);
            }
            catch
            {
                // Fallback to XAML background
            }

            RequestId = requestId;
            PermissionTypeBlock.Text = string.IsNullOrEmpty(permissionType) ? "Unknown Action" : permissionType;
            PermissionDetailBlock.Text = string.IsNullOrEmpty(detail) ? "No details provided." : detail;
            WorkingDirBlock.Text = string.IsNullOrEmpty(workingDir) ? "Unknown" : workingDir;

            ApplyRiskLevel(riskLevel ?? "Medium");
        }

        /// <summary>
        /// Applies color coding to the risk chip, header icon, and note text based on risk level.
        /// </summary>
        private void ApplyRiskLevel(string risk)
        {
            string chipColor;
            string chipBg;
            string iconGlyph;
            string noteText;

            switch (risk.ToLowerInvariant())
            {
                case "low":
                    chipColor = "#10B981";  // green
                    chipBg = "#052E16";
                    iconGlyph = "\uE72E";   // Shield
                    noteText = "This is a low-risk, read-only operation. Allow Once is recommended.";
                    break;
                case "high":
                    chipColor = "#EF4444";  // red
                    chipBg = "#450A0A";
                    iconGlyph = "\uE814";   // Warning shield / alert
                    noteText = "This is a HIGH-RISK operation and may be irreversible. Review carefully before allowing.";
                    break;
                default: // Medium
                    chipColor = "#F59E0B";  // amber
                    chipBg = "#451A03";
                    iconGlyph = "\uE72E";   // Shield
                    noteText = "This operation modifies state. Always Allow will create a rule for this action pattern.";
                    break;
            }

            var brush = (Brush)new BrushConverter().ConvertFromString(chipColor)!;
            var bgBrush = (Brush)new BrushConverter().ConvertFromString(chipBg)!;

            RiskLevelBlock.Text = risk;
            RiskLevelBlock.Foreground = brush;
            RiskChipBorder.BorderBrush = brush;
            RiskChipBorder.Background = bgBrush;
            RiskIconBlock.Foreground = brush;
            RiskNoteBlock.Text = noteText;
        }

        private void RejectButton_Click(object sender, RoutedEventArgs e)
        {
            UserDecision = "deny";
            this.DialogResult = false;
            this.Close();
        }

        private void ApproveOnceButton_Click(object sender, RoutedEventArgs e)
        {
            UserDecision = "allow";
            this.DialogResult = true;
            this.Close();
        }

        private void AlwaysAllowButton_Click(object sender, RoutedEventArgs e)
        {
            UserDecision = "always";
            this.DialogResult = true;
            this.Close();
        }
    }
}
