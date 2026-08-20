BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientConnectivityChecker.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientConnectivityChecker -Force -ErrorAction SilentlyContinue
}

Describe 'Get-DnsChain' {
    It 'follows a chain of CNAME records' {
        InModuleScope GSAClientConnectivityChecker {
            Mock Resolve-DnsName {
                switch ($Name) {
                    'start.example.com' { @([PSCustomObject]@{ QueryType = 'CNAME'; NameHost = 'middle.example.com' }) }
                    'middle.example.com' { @([PSCustomObject]@{ QueryType = 'CNAME'; NameHost = 'end.example.com' }) }
                    'end.example.com' { @([PSCustomObject]@{ QueryType = 'A'; IPAddress = '1.2.3.4' }) }
                }
            }

            $chain = Get-DnsChain -fqdn 'start.example.com'

            $chain | Should -Be @('middle.example.com', 'end.example.com')
        }
    }

    It 'skips self-referential CNAMEs injected by GSA synthetic DNS' {
        InModuleScope GSAClientConnectivityChecker {
            Mock Resolve-DnsName { @([PSCustomObject]@{ QueryType = 'CNAME'; NameHost = 'loop.example.com' }) }

            $chain = Get-DnsChain -fqdn 'loop.example.com'

            $chain | Should -BeNullOrEmpty
        }
    }

    It 'stops following CNAMEs at the recursion depth limit' {
        InModuleScope GSAClientConnectivityChecker {
            Mock Resolve-DnsName {
                param($Name)
                @([PSCustomObject]@{ QueryType = 'CNAME'; NameHost = "$Name.next" })
            }

            $chain = Get-DnsChain -fqdn 'a'

            $chain.Count | Should -BeLessOrEqual 10
        }
    }

    It 'returns an empty array when DNS resolution fails' {
        InModuleScope GSAClientConnectivityChecker {
            Mock Resolve-DnsName { throw 'DNS failure' }
            $chain = Get-DnsChain -fqdn 'broken.example.com'
            $chain | Should -BeNullOrEmpty
        }
    }
}
