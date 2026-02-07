import React from 'react';

interface StackComposeEditorProps {
  value: string;
  onChange: (value: string) => void;
  readOnly?: boolean;
}

const COMPOSE_PLACEHOLDER = `version: '3.8'
services:
  web:
    image: nginx:latest
    ports:
      - "80:80"
    deploy:
      replicas: 3
      update_config:
        parallelism: 1
        delay: 10s
`;

export const StackComposeEditor: React.FC<StackComposeEditorProps> = ({ value, onChange, readOnly = false }) => {
  return (
    <div className="relative">
      <textarea
        className="input-theme w-full font-mono text-sm leading-relaxed min-h-[300px] resize-y"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={COMPOSE_PLACEHOLDER}
        readOnly={readOnly}
        spellCheck={false}
      />
      <div className="absolute top-2 right-2 text-xs text-theme-tertiary bg-theme-surface px-2 py-0.5 rounded">
        YAML
      </div>
    </div>
  );
};
