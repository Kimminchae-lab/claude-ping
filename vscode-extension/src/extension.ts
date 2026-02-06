import * as vscode from 'vscode';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';

interface NotificationOption {
    label: string;
    keystroke: string;
}

interface NotificationData {
    title: string;
    body: string;
    type: string;
    options: NotificationOption[];
}

let fileWatcher: fs.FSWatcher | undefined;
let processedFiles = new Set<string>();

export function activate(context: vscode.ExtensionContext) {
    console.log('Claude Ping extension is now active');

    // Register test command
    const testCommand = vscode.commands.registerCommand('claude-ping.showNotification', () => {
        showTestNotification();
    });
    context.subscriptions.push(testCommand);

    // Start watching the queue directory
    startWatching();

    // Re-start watching when configuration changes
    vscode.workspace.onDidChangeConfiguration(e => {
        if (e.affectsConfiguration('claudePing')) {
            stopWatching();
            startWatching();
        }
    });
}

export function deactivate() {
    stopWatching();
}

function getQueueDirectory(): string {
    const config = vscode.workspace.getConfiguration('claudePing');
    const watchDir = config.get<string>('watchDirectory', '~/.claude-notifier/queue');
    return watchDir.replace('~', os.homedir());
}

function startWatching() {
    const config = vscode.workspace.getConfiguration('claudePing');
    if (!config.get<boolean>('enabled', true)) {
        return;
    }

    const queueDir = getQueueDirectory();

    // Ensure directory exists
    if (!fs.existsSync(queueDir)) {
        fs.mkdirSync(queueDir, { recursive: true });
    }

    // Watch for new files
    fileWatcher = fs.watch(queueDir, (eventType, filename) => {
        if (eventType === 'rename' && filename && filename.endsWith('.json')) {
            const filePath = path.join(queueDir, filename);

            // Delay to ensure file is fully written
            setTimeout(() => {
                processNotificationFile(filePath);
            }, 100);
        }
    });

    // Also check for existing files on startup
    checkExistingFiles(queueDir);

    console.log(`Claude Ping: Watching ${queueDir}`);
}

function stopWatching() {
    if (fileWatcher) {
        fileWatcher.close();
        fileWatcher = undefined;
    }
}

function checkExistingFiles(queueDir: string) {
    try {
        const files = fs.readdirSync(queueDir).filter(f => f.endsWith('.json'));
        for (const file of files) {
            const filePath = path.join(queueDir, file);
            processNotificationFile(filePath);
        }
    } catch (error) {
        // Directory might not exist yet
    }
}

function processNotificationFile(filePath: string) {
    // Skip if already processed
    if (processedFiles.has(filePath)) {
        return;
    }

    try {
        if (!fs.existsSync(filePath)) {
            return;
        }

        const content = fs.readFileSync(filePath, 'utf8');
        const notification: NotificationData = JSON.parse(content);

        // Mark as processed and delete file
        processedFiles.add(filePath);
        fs.unlinkSync(filePath);

        // Clean up processed files set periodically
        if (processedFiles.size > 100) {
            processedFiles.clear();
        }

        // Show notification based on type
        if (notification.type === 'ask') {
            showAskNotification(notification);
        } else if (notification.type === 'permission') {
            showPermissionNotification(notification);
        } else {
            showSimpleNotification(notification);
        }
    } catch (error) {
        console.error('Claude Ping: Error processing notification file', error);
    }
}

async function showAskNotification(notification: NotificationData) {
    const options = notification.options.slice(0, 4);
    const buttons = options.map(opt => opt.label);
    buttons.push('Other...');

    const selection = await vscode.window.showInformationMessage(
        `${notification.title}: ${notification.body}`,
        { modal: false },
        ...buttons
    );

    if (selection === 'Other...') {
        // Focus terminal for custom input
        focusTerminal();
    } else if (selection) {
        const selectedOption = options.find(opt => opt.label === selection);
        if (selectedOption) {
            sendToTerminal(selectedOption.keystroke);
        }
    }
}

async function showPermissionNotification(notification: NotificationData) {
    const selection = await vscode.window.showInformationMessage(
        `${notification.title}: ${notification.body}`,
        { modal: false },
        'Yes',
        'No'
    );

    if (selection === 'Yes') {
        sendToTerminal('y');
    } else if (selection === 'No') {
        sendToTerminal('n');
    }
}

function showSimpleNotification(notification: NotificationData) {
    vscode.window.showInformationMessage(`${notification.title}: ${notification.body}`);
}

function showTestNotification() {
    vscode.window.showInformationMessage(
        'Claude Ping: Test notification',
        'Option 1',
        'Option 2',
        'Other...'
    ).then(selection => {
        if (selection) {
            vscode.window.showInformationMessage(`You selected: ${selection}`);
        }
    });
}

function sendToTerminal(text: string) {
    const terminal = vscode.window.activeTerminal || vscode.window.terminals[0];

    if (terminal) {
        terminal.show();
        terminal.sendText(text, true);
    } else {
        // Create a new terminal if none exists
        const newTerminal = vscode.window.createTerminal('Claude');
        newTerminal.show();
        newTerminal.sendText(text, true);
    }
}

function focusTerminal() {
    const terminal = vscode.window.activeTerminal || vscode.window.terminals[0];

    if (terminal) {
        terminal.show();
    } else {
        const newTerminal = vscode.window.createTerminal('Claude');
        newTerminal.show();
    }
}
