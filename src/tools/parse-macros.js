/**
 * Bixoft Macro Parser
 * Extracts macro definitions and control block fields into JSON database
 */

const fs = require('fs');
const path = require('path');

const MACRO_DIR = path.join(__dirname, '../../resources/bixoft-macros');
const OUTPUT_FILE = path.join(__dirname, '../../data/macros.json');

// Categories based on macro name patterns
function categorize(name) {
    if (name.startsWith('MAP')) return 'Control Blocks';
    if (name.startsWith('CHK')) return 'Type Checking';
    if (name.startsWith('BAL') || name.startsWith('BAS')) return 'Branch Instructions';
    if (name.startsWith('EQU')) return 'Equates';
    if (['IF', 'ELSE', 'ENDIF', 'DO', 'ENDDO', 'CASE', 'ENDCASE', 'WHEN'].includes(name)) return 'Structured Programming';
    if (['PGM', 'PGM0', 'BEGSR', 'ENDSR', 'EXSR'].includes(name)) return 'Program Structure';
    if (name.startsWith('EX')) return 'Execute Instructions';
    return 'Miscellaneous';
}

// Manual descriptions for well-known macros
const MANUAL_DESCRIPTIONS = {
    'EQUREG': 'Declare a register with a specific type for strong type checking',
    'CHKREG': 'Verify that a register matches the expected type',
    'CHKNUM': 'Verify that an argument contains a valid numeric literal value',
    'CHKLIT': 'Verify that an argument is a valid literal',
    'CHKMAP': 'Check parameters for MAP macros',
    'CHKLIC': 'Check license acceptance for BXA macro library',
    'IF': 'Start conditional block (structured programming)',
    'ELSE': 'Else clause for IF block',
    'ENDIF': 'End IF block',
    'DO': 'Start loop block (structured programming)',
    'ENDDO': 'End DO loop block',
    'CASE': 'Start CASE block for multi-way branching',
    'WHEN': 'Case selector within CASE block',
    'ENDCASE': 'End CASE block',
    'PGM': 'Program entry point with standard linkage conventions',
    'PGM0': 'Lightweight program entry point',
    'BEGSR': 'Begin subroutine definition',
    'ENDSR': 'End subroutine definition',
    'EXSR': 'Execute subroutine',
    'USEDREGS': 'Display currently used registers',
    'USE': 'Mark register as in use',
    'DROP': 'Release register from use tracking',
    'MAPDCB': 'Map Data Control Block (DCB) fields',
    'MAPTCB': 'Map Task Control Block (TCB) fields',
    'MAPASCB': 'Map Address Space Control Block (ASCB) fields',
    'MAPACB': 'Map Access Method Control Block (ACB) fields',
    'MAPRPL': 'Map Request Parameter List (RPL) fields',
    'MAPJFCB': 'Map Job File Control Block (JFCB) fields',
    'MAPDSCB': 'Map Data Set Control Block (DSCB) fields',
    'MAPPSA': 'Map Prefixed Save Area (PSA) fields',
    'MAPCVT': 'Map Communication Vector Table (CVT) fields',
    'MAPECB': 'Map Event Control Block (ECB) fields',
    'MAPIOB': 'Map Input/Output Block (IOB) fields',
    'MAPSRB': 'Map Service Request Block (SRB) fields',
    'MAPUCB': 'Map Unit Control Block (UCB) fields',
    // Branch macros
    'BALC': 'Branch and link on condition (carry)',
    'BALE': 'Branch and link on equal',
    'BALH': 'Branch and link on high',
    'BALL': 'Branch and link on low',
    'BALM': 'Branch and link on mixed',
    'BALNE': 'Branch and link on not equal',
    'BALNH': 'Branch and link on not high',
    'BALNL': 'Branch and link on not low',
    'BALNM': 'Branch and link on not mixed',
    'BALNO': 'Branch and link on not overflow',
    'BALNP': 'Branch and link on not plus',
    'BALNZ': 'Branch and link on not zero',
    'BALO': 'Branch and link on overflow',
    'BALP': 'Branch and link on plus',
    'BALZ': 'Branch and link on zero',
};

// Extract description from comment header
function extractDescription(content, name) {
    // Check manual descriptions first
    if (MANUAL_DESCRIPTIONS[name]) {
        return MANUAL_DESCRIPTIONS[name];
    }

    const lines = content.split('\n');
    let desc = '';
    let foundMacroSection = false;

    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];

        // Skip license boilerplate - look for actual description after MACRO statement
        if (line.trim() === 'MACRO') {
            foundMacroSection = true;
            continue;
        }

        // After MACRO, look for description comments
        if (foundMacroSection && line.startsWith('.*')) {
            const text = line.substring(2).trim();
            // Skip empty lines and separator lines
            if (text === '' || text.match(/^\*+$/)) continue;
            // Found actual description
            if (text && !text.includes('IMPORTANT NOTICE')) {
                desc = text;
                // Collect continuation lines
                for (let j = i + 1; j < lines.length && j < i + 5; j++) {
                    const nextLine = lines[j];
                    if (nextLine.startsWith('.*')) {
                        const nextText = nextLine.substring(2).trim();
                        if (nextText && !nextText.match(/^\*+$/) && !nextText.startsWith('&')) {
                            desc += ' ' + nextText;
                        } else {
                            break;
                        }
                    } else {
                        break;
                    }
                }
                break;
            }
        }
    }

    // Generate description for MAP macros
    if (!desc && name.startsWith('MAP')) {
        const blockName = name.replace('MAP', '');
        desc = `Map ${blockName} control block fields`;
    }

    return desc.trim() || 'Bixoft macro';
}

// Extract parameters from macro prototype
function extractParameters(content) {
    const params = [];
    const lines = content.split('\n');
    let inMacro = false;
    let protoLine = '';

    for (const line of lines) {
        if (line.trim() === 'MACRO') {
            inMacro = true;
            continue;
        }
        if (inMacro) {
            // Skip comment lines
            if (line.startsWith('.*')) continue;

            // Collect prototype line (may span multiple lines)
            protoLine += line;

            // Check for continuation
            if (!line.endsWith('*')) {
                break;
            }
        }
    }

    // Parse parameters from prototype
    // Format: &LABEL   MACNAME &PARAM1=,&PARAM2=value,...
    const paramMatches = protoLine.matchAll(/&(\w+)=/g);
    for (const match of paramMatches) {
        if (match[1] !== 'LABEL') {
            params.push(match[1]);
        }
    }

    return params;
}

// Extract control block fields from MAPxxx macros
function extractControlBlockFields(name, content) {
    const fields = [];
    const blockName = name.replace('MAP', '');
    const lines = content.split('\n');

    // Look for DSOVR declarations - these define storage fields
    // Format: FIELDNAME DSOVR type   or   FIELDNAME DSOVR *NEWNAME,target
    const dsovrPattern = /^(\w+)\s+DSOVR\s+(\S+)/gm;
    let match;

    while ((match = dsovrPattern.exec(content)) !== null) {
        const fieldName = match[1];
        const typeSpec = match[2];

        // Skip control directives
        if (typeSpec.startsWith('*')) continue;

        // Parse type: X, XL3, AL2, H, F, etc.
        const typeMatch = typeSpec.match(/^0?([XAFHCBDEP])L?(\d+)?/i);
        if (typeMatch) {
            const baseType = typeMatch[1].toUpperCase();
            const length = parseInt(typeMatch[2]) || getDefaultLength(baseType);

            fields.push({
                name: fieldName,
                storageType: baseType,
                length: length,
                fieldType: 'storage',
                description: getTypeDescription(baseType, length)
            });
        }
    }

    // Look for EQUOVR declarations - bit fields and code values
    // Format: FIELDNAME EQUOVR ,,type,parentField
    const equovrPattern = /^(\w+)\s+EQUOVR\s+,+(\w*),(\w+)/gm;

    while ((match = equovrPattern.exec(content)) !== null) {
        const fieldName = match[1];
        const fieldType = match[2] || 'v';  // v=value, b=bit
        const parentField = match[3];

        fields.push({
            name: fieldName,
            fieldType: fieldType === 'b' ? 'bit' : 'code',
            parent: parentField,
            description: fieldType === 'b'
                ? `Bit in ${parentField}`
                : `Code value for ${parentField}`
        });
    }

    // Look for DS declarations with comments
    // Format: FIELDNAME DS type   description in comment
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        const dsMatch = line.match(/^(\w+)\s+DS\s+(\S+)\s+(.*)/);
        if (dsMatch) {
            const fieldName = dsMatch[1];
            const typeSpec = dsMatch[2];
            let comment = dsMatch[3] || '';

            // Clean up comment
            comment = comment.replace(/^\*?\s*/, '').trim();

            // Check for continuation on next line
            if (i + 1 < lines.length && lines[i + 1].match(/^\*\s/)) {
                comment += ' ' + lines[i + 1].replace(/^\*\s*/, '').trim();
            }

            // Parse type
            const typeMatch = typeSpec.match(/^0?([XAFHCBDEP])L?(\d+)?/i);
            if (typeMatch) {
                const baseType = typeMatch[1].toUpperCase();
                const length = parseInt(typeMatch[2]) || getDefaultLength(baseType);

                // Only add if not already present from DSOVR
                if (!fields.find(f => f.name === fieldName)) {
                    fields.push({
                        name: fieldName,
                        storageType: baseType,
                        length: length,
                        fieldType: 'storage',
                        description: comment || getTypeDescription(baseType, length)
                    });
                }
            }
        }
    }

    // Look for DCL *CODE declarations
    // Format: FIELDNAME DCL *CODE,type,value1,value2,...
    const dclCodePattern = /^(\w+)\s+DCL\s+\*CODE,(\w+),(.+)/gm;
    while ((match = dclCodePattern.exec(content)) !== null) {
        const fieldName = match[1];
        const typeSpec = match[2];
        const values = match[3].split(',').map(v => v.trim().replace(/\*$/, ''));

        fields.push({
            name: fieldName,
            fieldType: 'codeField',
            storageType: typeSpec,
            values: values.filter(v => v && !v.startsWith('*')),
            description: `Code field with values: ${values.slice(0, 3).join(', ')}${values.length > 3 ? '...' : ''}`
        });
    }

    return fields;
}

function getDefaultLength(type) {
    switch (type) {
        case 'X': return 1;
        case 'A': return 4;
        case 'F': return 4;
        case 'H': return 2;
        case 'C': return 1;
        case 'B': return 1;
        case 'D': return 8;
        case 'E': return 4;
        case 'P': return 4;
        default: return 1;
    }
}

function getTypeDescription(type, length) {
    const types = {
        'X': 'Hexadecimal',
        'A': 'Address',
        'F': 'Fullword',
        'H': 'Halfword',
        'C': 'Character',
        'B': 'Binary',
        'D': 'Doubleword',
        'E': 'Floating point',
        'P': 'Packed decimal'
    };
    return `${types[type] || type} (${length} byte${length > 1 ? 's' : ''})`;
}

// Main parser
async function parseMacros() {
    const database = {
        version: '1.0.0',
        source: 'Bixoft eXtended Assembly Language',
        macros: [],
        controlBlocks: {}
    };

    const files = fs.readdirSync(MACRO_DIR).filter(f => f.endsWith('.mac'));
    console.log(`Found ${files.length} macro files`);

    for (const file of files) {
        const name = file.replace('.mac', '');
        const filePath = path.join(MACRO_DIR, file);
        const content = fs.readFileSync(filePath, 'utf-8');

        const macro = {
            name: name,
            description: extractDescription(content, name),
            category: categorize(name),
            parameters: extractParameters(content),
            source: 'Bixoft'
        };

        database.macros.push(macro);

        // Extract control block fields for MAP* macros
        if (name.startsWith('MAP')) {
            const blockName = name.replace('MAP', '');
            const fields = extractControlBlockFields(name, content);
            if (fields.length > 0) {
                database.controlBlocks[blockName] = {
                    macro: name,
                    description: macro.description,
                    fields: fields
                };
            }
        }
    }

    // Sort macros by name
    database.macros.sort((a, b) => a.name.localeCompare(b.name));

    // Write output
    const outputDir = path.dirname(OUTPUT_FILE);
    if (!fs.existsSync(outputDir)) {
        fs.mkdirSync(outputDir, { recursive: true });
    }

    fs.writeFileSync(OUTPUT_FILE, JSON.stringify(database, null, 2));

    // Statistics
    const categories = {};
    for (const macro of database.macros) {
        categories[macro.category] = (categories[macro.category] || 0) + 1;
    }

    console.log('\nParsed macros by category:');
    for (const [cat, count] of Object.entries(categories).sort((a, b) => b[1] - a[1])) {
        console.log(`  ${cat}: ${count}`);
    }

    console.log(`\nControl blocks: ${Object.keys(database.controlBlocks).length}`);
    let totalFields = 0;
    for (const block of Object.values(database.controlBlocks)) {
        totalFields += block.fields.length;
    }
    console.log(`Total fields: ${totalFields}`);

    console.log(`\nOutput written to: ${OUTPUT_FILE}`);
}

parseMacros().catch(console.error);
