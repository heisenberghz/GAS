using System;
using System.Windows;
using GAS.Core;

namespace GAS.App
{
    [System.Runtime.Versioning.SupportedOSPlatform("windows")]
    public partial class ApprovalWindow : Wpf.Ui.Controls.FluentWindow
    {
        public string RequestId { get; }
        public string UserDecision { get; private set; } = "deny";

        public ApprovalWindow(string requestId, string permissionType, string detail)
        {
            InitializeComponent();
            
            try
            {
                Wpf.Ui.Controls.WindowBackdrop.ApplyBackdrop(this, Wpf.Ui.Controls.WindowBackdropType.Mica);
            }
            catch
            {
                // Fallback to custom brush in XAML
            }

            RequestId = requestId;
            PermissionTypeBlock.Text = string.IsNullOrEmpty(permissionType) ? "Unknown Action" : permissionType;
            PermissionDetailBlock.Text = string.IsNullOrEmpty(detail) ? "No details provided." : detail;
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
