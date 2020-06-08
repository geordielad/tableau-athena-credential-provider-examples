
# Call AWS CLI to get STS Credentials as a Powershell Object
$credentials = aws sts get-session-token --duration-seconds 3600 --output json | ConvertFrom-Json
# Get the list of properties

# The actual credentials variables are in the child Credentials property
$namesAndValues = $credentials.Credentials

# Create a variable so we can iterate though the returned credentials properties
$varNames = $namesAndValues.PSObject.Properties.name

# For each property, create a var with its name and corresponding value
ForEach ($variable in $varNames) {

    # The STS property is of the form AccessKeyId 
    # so we do a bit of string magic to transform the name
    # example AccessKeyId becomes ACCESS_KEY_ID
    $fixed_variable = ($variable.Substring(0,1) + ($variable.Substring(1) -creplace '[A-Z]', '_$0')).ToUpper()

    # Create an environment variable for each STS property
    Set-Item -Path "Env:$fixed_variable" -Value $namesAndValues.$variable
    
}

# Now start Tableau Desktop.
# Desktop will use the athena.properties file to tell JDBC to look at the Credentials Chain
# and the JDBC driver will find the STS credentials in the environment variables.
Start-Process -FilePath "C:\Program Files\Tableau\Tableau 2020.1\bin\tableau.exe" -WorkingDirectory "C:\Program Files\Tableau\Tableau 2020.1"

