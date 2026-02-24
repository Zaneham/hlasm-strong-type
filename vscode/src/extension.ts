import * as vscode from 'vscode';
import * as path from 'path';
import * as fs from 'fs';
import {
    LanguageClient,
    LanguageClientOptions,
    ServerOptions,
} from 'vscode-languageclient/node';

/* ---- Macro Database (local, for tree view) ---- */

interface MacroDefinition {
    name: string;
    description: string;
    category?: string;
    parameters?: string[];
    source?: string;
    template?: string;
}

interface MacroDatabaseData {
    macros: MacroDefinition[];
    controlBlocks: {
        [blockName: string]: {
            description: string;
            fields: { name: string; description: string }[];
        };
    };
}

class MacroDatabase {
    private macros: Map<string, MacroDefinition> = new Map();
    private categories: Set<string> = new Set();

    load(dataPath: string): void {
        if (!fs.existsSync(dataPath)) { return; }
        try {
            const data: MacroDatabaseData = JSON.parse(
                fs.readFileSync(dataPath, 'utf-8')
            );
            if (data.macros) {
                for (const macro of data.macros) {
                    this.macros.set(macro.name.toUpperCase(), macro);
                    if (macro.category) {
                        this.categories.add(macro.category);
                    }
                }
            }
        } catch (e) {
            console.error('Failed to load macro database:', e);
        }
    }

    get macroCount(): number { return this.macros.size; }

    getMacro(name: string): MacroDefinition | undefined {
        return this.macros.get(name.toUpperCase());
    }

    getCategories(): string[] {
        return Array.from(this.categories).sort();
    }

    getMacrosByCategory(category: string): MacroDefinition[] {
        return Array.from(this.macros.values())
            .filter(m => m.category === category)
            .sort((a, b) => a.name.localeCompare(b.name));
    }

    getAllMacros(): MacroDefinition[] {
        return Array.from(this.macros.values())
            .sort((a, b) => a.name.localeCompare(b.name));
    }
}

/* ---- Tree View ---- */

class MacroTreeItem extends vscode.TreeItem {
    constructor(
        public readonly label: string,
        public readonly collapsibleState: vscode.TreeItemCollapsibleState,
        public readonly contextValue: string
    ) {
        super(label, collapsibleState);
    }
}

class MacroTreeProvider implements vscode.TreeDataProvider<MacroTreeItem> {
    private _onDidChange = new vscode.EventEmitter<MacroTreeItem | undefined | null | void>();
    readonly onDidChangeTreeData = this._onDidChange.event;

    constructor(private db: MacroDatabase) {}

    refresh(): void { this._onDidChange.fire(); }

    getTreeItem(element: MacroTreeItem): vscode.TreeItem { return element; }

    getChildren(element?: MacroTreeItem): MacroTreeItem[] {
        if (!element) {
            return this.db.getCategories().map(cat => {
                const count = this.db.getMacrosByCategory(cat).length;
                const item = new MacroTreeItem(
                    cat, vscode.TreeItemCollapsibleState.Collapsed, 'category'
                );
                item.description = `${count} macros`;
                item.iconPath = this.categoryIcon(cat);
                return item;
            });
        }
        if (element.contextValue === 'category') {
            return this.db.getMacrosByCategory(element.label as string).map(macro => {
                const item = new MacroTreeItem(
                    macro.name, vscode.TreeItemCollapsibleState.None, 'macro'
                );
                const desc = macro.description || '';
                item.description = desc.length > 50 ? desc.substring(0, 50) + '...' : desc;
                item.iconPath = new vscode.ThemeIcon('symbol-function');
                item.command = {
                    command: 'hlasm.insertMacroFromTree',
                    title: 'Insert Macro',
                    arguments: [macro]
                };
                return item;
            });
        }
        return [];
    }

    private categoryIcon(cat: string): vscode.ThemeIcon {
        switch (cat) {
            case 'Type Checking': return new vscode.ThemeIcon('shield');
            case 'Structured Programming': return new vscode.ThemeIcon('git-merge');
            case 'Control Blocks': return new vscode.ThemeIcon('database');
            case 'Branch Instructions': return new vscode.ThemeIcon('git-branch');
            case 'Program Structure': return new vscode.ThemeIcon('file-code');
            case 'Equates': return new vscode.ThemeIcon('symbol-constant');
            default: return new vscode.ThemeIcon('symbol-misc');
        }
    }
}

/* ---- LSP Client ---- */

let client: LanguageClient | undefined;

function findServerBinary(extensionPath: string): string | undefined {
    const config = vscode.workspace.getConfiguration('hlasm');
    const configured = config.get<string>('serverPath');
    if (configured && fs.existsSync(configured)) { return configured; }

    const isWindows = process.platform === 'win32';
    const binaryName = isWindows ? 'hlasm-lsp.exe' : 'hlasm-lsp';
    const candidates = [
        path.join(extensionPath, 'server', binaryName),                      // bundled
        path.join(extensionPath, '..', '_build', 'default', 'bin', 'main.exe'),  // dev
        path.join(extensionPath, '..', '_build', 'default', 'bin', 'main'),      // dev
    ];

    for (const p of candidates) {
        if (fs.existsSync(p)) { return p; }
    }
    return undefined;
}

/* ---- Activation ---- */

export async function activate(context: vscode.ExtensionContext) {
    console.log('HLASM Strong Type Toolkit activating...');

    const extensionPath = context.extensionPath;

    // Load macro database for tree view
    const macroDb = new MacroDatabase();
    const dataPath = path.join(extensionPath, 'data', 'macros.json');
    macroDb.load(dataPath);

    // Tree view
    const treeProvider = new MacroTreeProvider(macroDb);
    context.subscriptions.push(
        vscode.window.createTreeView('hlasmMacroBrowser', {
            treeDataProvider: treeProvider,
            showCollapseAll: true
        })
    );

    // Commands
    context.subscriptions.push(
        vscode.commands.registerCommand('hlasm.showMacroBrowser', async () => {
            const cats = macroDb.getCategories();
            const cat = await vscode.window.showQuickPick(cats, {
                placeHolder: 'Select macro category'
            });
            if (!cat) { return; }
            const macros = macroDb.getMacrosByCategory(cat);
            const items = macros.map(m => ({
                label: m.name,
                description: m.description,
                detail: m.parameters?.join(', ')
            }));
            const sel = await vscode.window.showQuickPick(items, {
                placeHolder: 'Select macro'
            });
            if (sel) {
                const macro = macroDb.getMacro(sel.label);
                if (macro) {
                    const ch = vscode.window.createOutputChannel('HLASM Macro');
                    ch.clear();
                    ch.appendLine(`=== ${macro.name} ===`);
                    ch.appendLine(macro.description);
                    if (macro.parameters) {
                        ch.appendLine(`\nParameters: ${macro.parameters.join(', ')}`);
                    }
                    ch.show();
                }
            }
        }),
        vscode.commands.registerCommand('hlasm.insertMacro', async () => {
            const editor = vscode.window.activeTextEditor;
            if (!editor) { return; }
            const macros = macroDb.getAllMacros();
            const items = macros.map(m => ({
                label: m.name,
                description: m.category,
                detail: m.description
            }));
            const sel = await vscode.window.showQuickPick(items, {
                placeHolder: 'Select macro to insert'
            });
            if (sel) {
                const macro = macroDb.getMacro(sel.label);
                if (macro?.template) {
                    editor.insertSnippet(new vscode.SnippetString(macro.template));
                } else if (macro) {
                    const params = macro.parameters?.map(
                        (p, i) => `\${${i + 1}:${p}}`
                    ).join(',') || '';
                    editor.insertSnippet(
                        new vscode.SnippetString(`         ${macro.name}  ${params}`)
                    );
                }
            }
        }),
        vscode.commands.registerCommand('hlasm.refreshMacros', () => {
            treeProvider.refresh();
        }),
        vscode.commands.registerCommand('hlasm.insertMacroFromTree',
            (macro: MacroDefinition) => {
                const editor = vscode.window.activeTextEditor;
                if (!editor) {
                    vscode.window.showInformationMessage(
                        `${macro.name}: ${macro.description}`
                    );
                    return;
                }
                if (macro.template) {
                    editor.insertSnippet(new vscode.SnippetString(macro.template));
                } else {
                    const params = macro.parameters?.map(
                        (p, i) => `\${${i + 1}:${p}}`
                    ).join(',') || '';
                    editor.insertSnippet(
                        new vscode.SnippetString(`         ${macro.name}  ${params}`)
                    );
                }
            }
        )
    );

    // Start LSP client
    const serverBinary = findServerBinary(extensionPath);
    if (!serverBinary) {
        vscode.window.showWarningMessage(
            'HLASM LSP server not found. Hover, diagnostics, completion, ' +
            'and go-to-definition are unavailable. ' +
            'Build with: opam exec -- dune build'
        );
        console.log(`Loaded tree view with ${macroDb.macroCount} macros (no LSP server)`);
        return;
    }

    const dataDir = path.join(extensionPath, 'data');
    const args = ['--data-dir', dataDir];

    // Pass macro source directories for go-to-definition on .mac files
    const macroDirCandidates = [
        path.join(extensionPath, 'macros'),                          // bundled
        path.join(extensionPath, '..', 'resources', 'bixoft-macros'), // dev
    ];
    for (const dir of macroDirCandidates) {
        if (fs.existsSync(dir)) {
            args.push('--macro-dir', dir);
            break;
        }
    }
    const macroLibs = vscode.workspace.getConfiguration('hlasm')
        .get<string[]>('macroLibraries') || [];
    for (const lib of macroLibs) {
        if (fs.existsSync(lib)) {
            args.push('--macro-dir', lib);
        }
    }

    const serverOptions: ServerOptions = {
        command: serverBinary,
        args,
    };

    const clientOptions: LanguageClientOptions = {
        documentSelector: [
            { scheme: 'file', language: 'hlasm' },
            { scheme: 'file', language: 'asm' },
            { scheme: 'file', pattern: '**/*.asm' },
            { scheme: 'file', pattern: '**/*.mac' },
        ],
    };

    client = new LanguageClient(
        'hlasm-lsp',
        'HLASM Language Server',
        serverOptions,
        clientOptions
    );

    await client.start();
    console.log(
        `HLASM Strong Type Toolkit activated. ` +
        `${macroDb.macroCount} macros, LSP server running.`
    );
}

export async function deactivate(): Promise<void> {
    if (client) {
        await client.stop();
    }
}
