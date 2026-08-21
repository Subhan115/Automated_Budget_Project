💰 Automated Azure Budget Guardrail System

An automated Azure cost-monitoring and notification system that detects when an Azure Budget threshold is exceeded, identifies the highest-cost resource, and sends an email notification with direct Azure Portal management links.

The project combines Azure Cost Management, Azure Budgets, Azure Monitor Action Groups, Azure Logic Apps, Managed Identity, and Azure RBAC to create an automated cost guardrail.

---

🚀 How It Works

The workflow follows this process:

Azure Budget
     │
     │ Threshold exceeded
     ▼
Azure Monitor Action Group
     │
     │ HTTP Webhook
     ▼
Azure Logic App
     │
     │ Query Cost Management
     ▼
Azure Cost Management
     │
     │ Aggregate & rank resources
     ▼
Highest-Cost Resource
     │
     ▼
Email Notification
     │
     ├── Budget information
     ├── Cost information
     ├── Highest-cost resource
     ├── Timestamp
     └── Azure Portal management link

When the configured budget threshold is exceeded, the Azure Monitor Action Group invokes the Logic App through its HTTP webhook.

The Logic App then queries Azure Cost Management data, ranks resources by accrued cost, identifies the highest-cost resource, and sends an email containing the relevant information and Azure Portal links.

---

✨ Features

💰 Azure Budget Monitoring

- Monitors Azure spending against a configured budget.
- Triggers when the configured threshold is exceeded.

🔔 Azure Monitor Action Group

- Receives the budget threshold event.
- Invokes the Logic App webhook.

⚙️ Azure Logic App Automation

- Processes the budget alert.
- Queries Azure Cost Management.
- Identifies the highest-cost resource.

🔐 Managed Identity & RBAC

- The Logic App uses a System-Assigned Managed Identity.
- Azure RBAC grants the Logic App permission to read Cost Management data.
- No Cost Management credentials are hardcoded into the workflow.

📊 Cost Analysis

- Queries cost information.
- Aggregates costs by resource.
- Ranks resources according to accrued cost.
- Identifies the resource with the highest cost.

📧 Automated Email Notifications

- Sends an email when the budget threshold is exceeded.
- Includes relevant budget and cost information.

🔗 Azure Portal Management Links

- Provides a direct link to the affected resource.
- Allows administrators to quickly review and manage the resource.

---

🏗️ Architecture

Azure Control & Provisioning Layer

The project uses:

- Microsoft Entra ID
- Azure Resource Manager
- Azure Cost Management Budget
- Azure Monitor Action Group
- Azure Logic App
- Logic App HTTP Webhook

The infrastructure is deployed and configured through Azure deployment resources.

Cost Monitoring & Decision Layer

After receiving a budget alert, the Logic App:

1. Receives the threshold event.
2. Determines the relevant subscription and budget period.
3. Queries Azure Cost Management.
4. Aggregates cost information by resource.
5. Ranks resources by accrued cost.
6. Identifies the highest-cost resource.

Notification Layer

The Logic App then:

1. Composes the alert details.
2. Includes budget and cost information.
3. Includes the highest-cost resource.
4. Adds an Azure Portal management URL.
5. Sends the notification to the configured recipient.

---

🔐 Security

Security is a core part of this project.

Managed Identity

The Logic App uses a System-Assigned Managed Identity instead of storing credentials inside the workflow.

Logic App
    │
    ▼
System-Assigned Managed Identity
    │
    ▼
Azure RBAC
    │
    ▼
Cost Management Read Access

The Logic App's managed identity is assigned the required Azure RBAC permissions to read Cost Management data.

This allows the Logic App to query the cost information required by the workflow without storing credentials or API secrets.

Least-Privilege Access

The RBAC assignment should be scoped as narrowly as practical while still allowing the Logic App to access the required Cost Management data.

---

📧 Email Notification

The generated notification can contain:

- Budget threshold
- Current cost information
- Subscription information
- Highest-cost resource
- Timestamp
- Azure Portal resource management link

This provides a direct path from the alert to investigation:

💰 Budget Alert
      │
      ▼
📧 Email Notification
      │
      ▼
🔗 Azure Portal
      │
      ▼
🛠️ Review / Manage Resource

---

🛠️ Azure Services Used

Service| Purpose
Azure Cost Management| Cost analysis and budget monitoring
Azure Budget| Defines the spending threshold
Azure Monitor Action Group| Receives and forwards the budget alert
Azure Logic Apps| Automates cost analysis and notification
Microsoft Entra ID| Identity and authentication
Azure RBAC| Grants the Logic App Cost Management read access
Azure Resource Manager| Resource provisioning and management
Outlook / Email Connector| Sends cost notifications

---

📋 Prerequisites

Before deploying the project, make sure you have:

- An active Azure subscription
- Azure CLI installed
- Azure CLI authenticated
- Permission to create the required Azure resources
- Permission to configure Azure RBAC
- An email address for receiving notifications

Login to Azure

az login

Check the Active Subscription

az account show

Select a Subscription

If you have multiple subscriptions:

az account set --subscription "<SUBSCRIPTION_ID>"

---

🚀 Deployment

Configure the required parameters before deployment, such as:

- Logic App name
- Notification email address
- Azure region
- Budget amount
- Budget threshold configuration

Example Deployment

az deployment group create \
  --resource-group "<RESOURCE_GROUP>" \
  --template-file azuredeploy.json \
  --parameters \
      logicAppName="BudgetSystem" \
      recipientEmail="<YOUR_EMAIL>"

«Adjust the deployment command according to the parameters defined in your deployment template.»

---

🔑 RBAC Configuration

The Logic App requires permission to read Azure Cost Management data.

The permission flow is:

Logic App
    │
    ▼
System-Assigned Managed Identity
    │
    ▼
Azure RBAC Role Assignment
    │
    ▼
Cost Management Read Access

The RBAC assignment allows the Logic App to query the Cost Management data required to identify the highest-cost resource.

No access keys or Cost Management credentials need to be stored in the Logic App.

---

🧪 Testing

To test the system:

1. Deploy the Logic App.
2. Confirm that the Logic App's managed identity is enabled.
3. Verify that the required Cost Management RBAC permission is assigned.
4. Configure the Azure Budget.
5. Configure the Azure Monitor Action Group.
6. Connect the Action Group to the Logic App webhook.
7. Verify that the Logic App workflow is enabled.
8. Trigger or wait for a budget threshold event.
9. Verify that the Action Group invokes the Logic App.
10. Confirm that the Logic App can read Cost Management data.
11. Check the configured email inbox for the notification.

---

🔄 End-to-End Workflow

┌──────────────────────┐
│     Azure Budget     │
└──────────┬───────────┘
           │
           │ Threshold exceeded
           ▼
┌──────────────────────┐
│   Action Group       │
└──────────┬───────────┘
           │
           │ HTTP Webhook
           ▼
┌──────────────────────┐
│    Logic App         │
│                      │
│ Managed Identity     │
└──────────┬───────────┘
           │
           │ RBAC
           ▼
┌──────────────────────┐
│ Azure Cost           │
│ Management           │
└──────────┬───────────┘
           │
           │ Cost Data
           ▼
┌──────────────────────┐
│ Rank Resources       │
│ by Accrued Cost      │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ Highest-Cost         │
│ Resource             │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ Email Notification   │
│ + Portal Link        │
└──────────────────────┘

---

🧠 What This Project Demonstrates

This project demonstrates practical Azure cloud engineering concepts including:

- Infrastructure automation
- Azure Resource Manager
- Azure Cost Management
- Azure Budgets
- Azure Monitor Action Groups
- Azure Logic Apps
- Managed Identities
- Azure RBAC
- Cost Management APIs
- Event-driven automation
- Email notifications
- Azure resource management
- Cloud cost optimization

---

🔒 Security Notes

- Do not hardcode credentials or secrets.
- Use Managed Identity wherever possible.
- Grant the Logic App only the RBAC permissions it requires.
- Scope RBAC assignments appropriately.
- Keep the Logic App webhook protected.
- Never commit connection strings, access keys, passwords, or other secrets to GitHub.

---

📁 Project Structure

.
├── azuredeploy.json
├── README.md
└── ...

Additional deployment and configuration files may be included depending on the project version.

---

🎯 Project Goal

The goal of this project is to create an automated Azure cost guardrail that goes beyond simply reporting:

«"Your Azure budget was exceeded."»

Instead, the system attempts to answer:

«"Which resource is costing the most, and where can I manage it?"»

This makes budget alerts more actionable and helps reduce the time required to investigate unexpected Azure spending.

---

⚠️ Disclaimer

This project is intended for learning, experimentation, and cloud engineering practice.

Always review Azure RBAC permissions, budget configuration, Logic App workflows, and notification settings before using a similar architecture in a production environment.

---

👨‍💻 Author

Subhan Choudary

Learning Cloud Engineering & DevOps 🚀
