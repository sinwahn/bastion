class Templates:
    """The templates of bastion.nix by their word, and whether each is sealed."""

    def __init__(self, configuration, files):
        self.configuration = configuration
        self.files = files

    def has(self, word):
        return any(template.word == word for template in self.configuration.templates)

    def template(self, word):
        return next(template for template in self.configuration.templates if template.word == word)

    def words(self):
        return " or ".join(template.word for template in self.configuration.templates)

    def is_sealed(self, template):
        return self.files.exists(template.sealed)

    def sealed_names(self):
        return {template.name for template in self.configuration.templates if self.is_sealed(template)}

    configuration = None
    files = None
