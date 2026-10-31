export class McpError extends Error {
  readonly code: number;

  constructor(code: number, message: string) {
    super(message);
    this.name = 'McpError';
    this.code = code;
  }
}

export class ToolInputError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ToolInputError';
  }
}