import conventional from '@commitlint/config-conventional';

const containsHan = (value) => /\p{Script=Han}/u.test(value ?? '');

const noHan = (field) => (parsed) => [
  !containsHan(parsed[field]),
  `${field} must not contain Unicode Han script characters`,
];

const canonicalLongProvenanceTrailers = [
  /^HMG-Provenance-Key-ID: ed25519-spki-sha256-[0-9a-f]{64}$/,
  /^HMG-Provenance-Signature-Ed25519: [A-Za-z0-9+/]{86}==$/,
];

const boundedFooterLines = (parsed, _when, limit = 100) => {
  const invalidLines = (parsed.footer ?? '')
    .split('\n')
    .filter(
      (line) =>
        line.length > limit &&
        !canonicalLongProvenanceTrailers.some((pattern) => pattern.test(line)),
    );

  return [
    invalidLines.length === 0,
    `footer lines must not exceed ${limit} characters unless they are canonical HMG provenance trailers`,
  ];
};

export default {
  ...conventional,
  plugins: [
    {
      rules: {
        'subject-no-han': noHan('subject'),
        'body-no-han': noHan('body'),
        'footer-no-han': noHan('footer'),
        'footer-bounded-lines': boundedFooterLines,
      },
    },
  ],
  rules: {
    ...conventional.rules,
    // The two canonical cryptographic trailers exceed the conventional
    // 100-character limit. Disable the broad built-in rule and replace it
    // with a strict shape-aware exception.
    'footer-max-line-length': [0],
    'footer-bounded-lines': [2, 'always', 100],
    'subject-no-han': [2, 'always'],
    'body-no-han': [2, 'always'],
    'footer-no-han': [2, 'always'],
  },
};
